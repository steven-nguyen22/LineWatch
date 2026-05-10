// snapshot-lines-mlb
//
// Captures the consensus run-line spread for MLB games starting in the next
// 25-35 minutes. Runs every 5 minutes via pg_cron — each game gets caught
// by at least one tick of this 10-minute window.
//
// Team-only V1 — player props (batter hits, pitcher Ks, etc.) come later
// as a separate task. Output rows in `team_game_results` have `spread_line`
// set but `actual_margin` / `covered` left NULL. The companion
// `fetch-mlb-game-results` function fills those in once the box score is final.
//
// Why ESPN event ID for game_id (not Odds API event ID): the post-game
// grader pulls from ESPN, so using ESPN's ID as the canonical key makes the
// UPDATE join trivial. We resolve ESPN's ID at snapshot time by hitting
// ESPN's daily scoreboard and matching on team names.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

const SPORT_KEY = "baseball_mlb";

// 10-minute band centered ~30 min before first pitch — a 5-minute cron
// always catches every game at least once.
const SNAPSHOT_MIN_MINUTES = 25;
const SNAPSHOT_MAX_MINUTES = 35;

interface OddsEvent {
  id: string;
  commence_time: string;
  home_team: string;
  away_team: string;
  bookmakers?: Array<{
    key: string;
    title: string;
    markets: Array<{
      key: string;
      outcomes: Array<{
        name: string;
        price: number;
        point?: number;
        description?: string;
      }>;
    }>;
  }>;
}

interface ESPNScoreboardEvent {
  id: string;
  competitions?: Array<{
    competitors?: Array<{
      team?: { displayName?: string };
      homeAway?: string;
    }>;
  }>;
}

/** Mode of a numeric array; ties broken by lower value (matches the iOS UI). */
function consensusPoint(points: number[]): number | null {
  if (points.length === 0) return null;
  const counts = new Map<number, number>();
  for (const p of points) counts.set(p, (counts.get(p) ?? 0) + 1);
  let bestPoint = points[0];
  let bestCount = -1;
  for (const [pt, ct] of counts) {
    if (ct > bestCount || (ct === bestCount && pt < bestPoint)) {
      bestPoint = pt;
      bestCount = ct;
    }
  }
  return bestPoint;
}

/** Look up ESPN event ID for a game by hitting the daily scoreboard. */
async function findESPNGameId(
  homeTeam: string,
  awayTeam: string,
  commenceTime: Date,
): Promise<string | null> {
  // Try both the local-date and UTC-date views in case the game crosses
  // midnight ET (late MLB games can show up on either day).
  const datesToTry = new Set<string>();
  for (const offsetHours of [-5, 0]) {
    const d = new Date(commenceTime.getTime() + offsetHours * 3600_000);
    const yyyy = d.getUTCFullYear();
    const mm = String(d.getUTCMonth() + 1).padStart(2, "0");
    const dd = String(d.getUTCDate()).padStart(2, "0");
    datesToTry.add(`${yyyy}${mm}${dd}`);
  }

  for (const dateStr of datesToTry) {
    const url = `https://site.api.espn.com/apis/site/v2/sports/baseball/mlb/scoreboard?dates=${dateStr}`;
    try {
      const res = await fetch(url);
      if (!res.ok) continue;
      const body = await res.json();
      const events: ESPNScoreboardEvent[] = body?.events ?? [];
      for (const ev of events) {
        const comps = ev.competitions?.[0]?.competitors ?? [];
        const home = comps.find((c) => c.homeAway === "home")?.team?.displayName ?? "";
        const away = comps.find((c) => c.homeAway === "away")?.team?.displayName ?? "";
        if (
          home.toLowerCase() === homeTeam.toLowerCase() &&
          away.toLowerCase() === awayTeam.toLowerCase()
        ) {
          return ev.id;
        }
      }
    } catch {
      // try next date
    }
  }
  return null;
}

Deno.serve(async (req) => {
  // service-role JWT gate (same pattern as every other edge fn)
  const auth = req.headers.get("authorization") ?? "";
  const token = auth.replace(/^Bearer\s+/i, "");
  try {
    const [, payloadB64] = token.split(".");
    const payload = JSON.parse(atob(payloadB64.replace(/-/g, "+").replace(/_/g, "/")));
    if (payload.role !== "service_role") {
      return new Response(JSON.stringify({ error: "unauthorized" }), {
        status: 401,
        headers: { "Content-Type": "application/json" },
      });
    }
  } catch {
    return new Response(JSON.stringify({ error: "unauthorized" }), {
      status: 401,
      headers: { "Content-Type": "application/json" },
    });
  }

  const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);
  const now = Date.now();
  const minTipMs = now + SNAPSHOT_MIN_MINUTES * 60_000;
  const maxTipMs = now + SNAPSHOT_MAX_MINUTES * 60_000;

  // ---------------------------------------------------------------------------
  // Load MLB cached_odds → find events first-pitching in our snapshot window
  // ---------------------------------------------------------------------------
  const { data: oddsRow, error: oddsErr } = await supabase
    .from("cached_odds")
    .select("data")
    .eq("sport_key", SPORT_KEY)
    .maybeSingle();

  if (oddsErr || !oddsRow) {
    return new Response(
      JSON.stringify({ error: "no cached odds", details: oddsErr?.message }),
      { status: 502, headers: { "Content-Type": "application/json" } },
    );
  }

  const allEvents: OddsEvent[] = oddsRow.data ?? [];
  const dueEvents = allEvents.filter((e) => {
    const tip = new Date(e.commence_time).getTime();
    return tip >= minTipMs && tip <= maxTipMs;
  });

  if (dueEvents.length === 0) {
    return new Response(
      JSON.stringify({ success: true, snapshotted: 0, reason: "no games in window" }),
      { headers: { "Content-Type": "application/json" } },
    );
  }

  // ---------------------------------------------------------------------------
  // Pre-load MLB team ID lookup (one query, cached for run)
  // ---------------------------------------------------------------------------
  const { data: teamRows } = await supabase
    .from("mlb_teams")
    .select("team_name, espn_id");

  const teamLookup = new Map<string, number>();
  for (const t of teamRows ?? []) {
    teamLookup.set(t.team_name, t.espn_id);
  }

  // ---------------------------------------------------------------------------
  // For each upcoming game: capture consensus run-line, resolve ESPN ID,
  // and write rows to `team_game_results`.
  // ---------------------------------------------------------------------------
  let teamInserts = 0;
  let skippedNoEspnId = 0;

  for (const event of dueEvents) {
    const tipDate = new Date(event.commence_time);
    const gameDate = tipDate.toISOString().slice(0, 10); // YYYY-MM-DD

    const espnGameId = await findESPNGameId(event.home_team, event.away_team, tipDate);
    if (!espnGameId) {
      skippedNoEspnId++;
      continue;
    }

    // Walk spreads market across all bookmakers, group by team name. In MLB
    // the "spread" is the run line — usually -1.5/+1.5 — but the OddsAPI
    // market key is still `spreads` (same as NBA), so the logic is identical.
    const teamSpreadPoints: Record<string, number[]> = {
      [event.home_team]: [],
      [event.away_team]: [],
    };
    for (const bm of event.bookmakers ?? []) {
      const spread = bm.markets.find((m) => m.key === "spreads");
      if (!spread) continue;
      for (const o of spread.outcomes) {
        if (o.point === undefined) continue;
        if (teamSpreadPoints[o.name] !== undefined) {
          teamSpreadPoints[o.name].push(o.point);
        }
      }
    }

    for (const [teamName, points] of Object.entries(teamSpreadPoints)) {
      const consensus = consensusPoint(points);
      if (consensus === null) continue;
      const espnId = teamLookup.get(teamName);
      if (!espnId) continue;
      const { error } = await supabase
        .from("team_game_results")
        .upsert(
          {
            team_espn_id: espnId,
            team_name: teamName,
            sport_key: SPORT_KEY,
            game_id: espnGameId,
            game_date: gameDate,
            spread_line: consensus,
          },
          { onConflict: "game_id,team_espn_id", ignoreDuplicates: true },
        );
      if (!error) teamInserts++;
    }
  }

  return new Response(
    JSON.stringify({
      success: true,
      games_in_window: dueEvents.length,
      team_rows_inserted: teamInserts,
      skipped_no_espn_id: skippedNoEspnId,
    }),
    { headers: { "Content-Type": "application/json" } },
  );
});
