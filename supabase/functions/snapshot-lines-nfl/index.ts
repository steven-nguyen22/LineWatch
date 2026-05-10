// snapshot-lines-nfl
//
// Captures the consensus NFL spread AND consensus player-prop lines
// (passing yards, rushing yards, receiving yards) for games kicking off
// in the next 25-35 minutes. Runs every 5 minutes via pg_cron — each
// game gets caught by at least one tick of this 10-minute window.
//
// Output rows in `team_game_results` and `player_game_results` have the
// `spread_line` / `line_value` set but `actual_margin`/`actual_value` left
// NULL. The companion `fetch-nfl-game-results` function fills those in
// once the scoreboard / box score is final.
//
// Why ESPN event ID for game_id (not Odds API event ID): the post-game
// grader pulls from ESPN, so using ESPN's ID as the canonical key makes the
// UPDATE join trivial. We resolve ESPN's ID at snapshot time by hitting
// ESPN's daily scoreboard and matching on team names.
//
// Player-ID resolution (player props):
//   `nfl_players` is the canonical (player_name, espn_id) lookup, populated
//   upstream by the `fetch-nfl-assets` function (which scans ESPN rosters
//   for all 32 teams). Players missing from `nfl_players` are silently
//   skipped here — the asset pipeline handles backfill. Position column
//   on the unified table is ignored at snapshot time; passing/rushing/
//   receiving lines map to whichever player is named in the prop.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

const ESPN_USER_AGENT = "LineWatch/1.0";

/**
 * fetch() wrapper for ESPN endpoints. Sets a real User-Agent (default
 * Deno UA looks bot-like) and logs non-2xx responses to `espn_failures`
 * for visibility — every other call site swallows these silently.
 */
// deno-lint-ignore no-explicit-any
async function espnFetch(url: string, supabase: any, fnName: string): Promise<Response> {
  let res: Response;
  try {
    res = await fetch(url, { headers: { "User-Agent": ESPN_USER_AGENT } });
  } catch (err) {
    await supabase.from("espn_failures").insert({
      function_name: fnName,
      url,
      status: null,
      error: err instanceof Error ? err.message : String(err),
    });
    throw err;
  }
  if (!res.ok) {
    await supabase.from("espn_failures").insert({
      function_name: fnName,
      url,
      status: res.status,
      error: null,
    });
  }
  return res;
}


const SPORT_KEY = "americanfootball_nfl";

// 10-minute band centered ~30 min before kickoff.
const SNAPSHOT_MIN_MINUTES = 25;
const SNAPSHOT_MAX_MINUTES = 35;

// Canonical Odds-API market keys we snapshot consensus for.
const PLAYER_PROP_MARKETS = [
  "player_pass_yds",
  "player_rush_yds",
  "player_reception_yds",
];

// Match Odds-API names against ESPN-canonical names already stored in
// `nfl_players.player_name`.
function normalizePlayerName(name: string): string {
  return name
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "")
    .toLowerCase()
    .replace(/[.,'-]/g, "")
    .replace(/\s+(jr|sr|ii|iii|iv)\b/g, "")
    .replace(/\s+/g, " ")
    .trim();
}

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

interface PropsRow {
  event_id: string;
  data: OddsEvent;
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

  // Cache scoreboard responses for the lifetime of this invocation.
  // Multiple games in the same start window share dates → without this
  // we'd re-fetch the same scoreboard URL once per game.
  const scoreboardCache = new Map<string, ESPNScoreboardEvent[]>();

  async function getScoreboardEvents(dateStr: string): Promise<ESPNScoreboardEvent[]> {
    if (scoreboardCache.has(dateStr)) return scoreboardCache.get(dateStr)!;
    const url = `https://site.api.espn.com/apis/site/v2/sports/football/nfl/scoreboard?dates=${dateStr}`;
    try {
      const res = await espnFetch(url, supabase, "snapshot-lines-nfl");
      const events: ESPNScoreboardEvent[] = res.ok ? ((await res.json())?.events ?? []) : [];
      scoreboardCache.set(dateStr, events);
      return events;
    } catch {
      scoreboardCache.set(dateStr, []);
      return [];
    }
  }

  /** Look up ESPN event ID for a game, using the per-invocation scoreboard cache. */
  async function findESPNGameId(
    homeTeam: string,
    awayTeam: string,
    commenceTime: Date,
  ): Promise<string | null> {
    const datesToTry = new Set<string>();
    for (const offsetHours of [-5, 0]) {
      const d = new Date(commenceTime.getTime() + offsetHours * 3600_000);
      const yyyy = d.getUTCFullYear();
      const mm = String(d.getUTCMonth() + 1).padStart(2, "0");
      const dd = String(d.getUTCDate()).padStart(2, "0");
      datesToTry.add(`${yyyy}${mm}${dd}`);
    }
    for (const dateStr of datesToTry) {
      const events = await getScoreboardEvents(dateStr);
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
    }
    return null;
  }


  // ---------------------------------------------------------------------------
  // Load NFL cached_odds → find events kicking off in our snapshot window
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
  // Pre-load NFL team + player ID lookups (one query each, cached for run)
  // ---------------------------------------------------------------------------
  const [{ data: teamRows }, { data: playerRows }] = await Promise.all([
    supabase.from("nfl_teams").select("team_name, espn_id"),
    supabase.from("nfl_players").select("player_name, espn_id, team_name"),
  ]);

  const teamLookup = new Map<string, number>();
  for (const t of teamRows ?? []) {
    teamLookup.set(t.team_name, t.espn_id);
  }

  // normalized player name -> { espn_id, canonical_name, team_name }
  const playerLookup = new Map<
    string,
    { espn_id: number; player_name: string; team_name: string }
  >();
  for (const p of playerRows ?? []) {
    if (!p.espn_id) continue;
    playerLookup.set(normalizePlayerName(p.player_name), {
      espn_id: p.espn_id,
      player_name: p.player_name,
      team_name: p.team_name,
    });
  }

  // ---------------------------------------------------------------------------
  // Pre-load cached player props for in-window event IDs (one shot)
  // ---------------------------------------------------------------------------
  const eventIds = dueEvents.map((e) => e.id);
  const { data: propsRows } = await supabase
    .from("cached_player_props")
    .select("event_id, data")
    .eq("sport_key", SPORT_KEY)
    .in("event_id", eventIds);

  const propsByEventId = new Map<string, PropsRow["data"]>();
  for (const r of (propsRows as PropsRow[]) ?? []) {
    propsByEventId.set(r.event_id, r.data);
  }

  // ---------------------------------------------------------------------------
  // For each upcoming game: capture consensus spread + player props,
  // resolve ESPN ID, and write rows.
  // ---------------------------------------------------------------------------
  let teamInserts = 0;
  let playerInserts = 0;
  let skippedNoEspnId = 0;

  for (const event of dueEvents) {
    const tipDate = new Date(event.commence_time);
    const gameDate = tipDate.toISOString().slice(0, 10); // YYYY-MM-DD

    const espnGameId = await findESPNGameId(event.home_team, event.away_team, tipDate);
    if (!espnGameId) {
      skippedNoEspnId++;
      continue;
    }

    // ---- TEAM SPREADS ------------------------------------------------------
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

    // ---- PLAYER PROPS (passing / rushing / receiving yards) ---------------
    const props = propsByEventId.get(event.id);
    if (!props) continue; // no player props cached for this event yet

    type Bucket = Map<string, Map<string, number[]>>;
    const buckets: Bucket = new Map();
    for (const bm of props.bookmakers ?? []) {
      for (const market of bm.markets ?? []) {
        if (!PLAYER_PROP_MARKETS.includes(market.key)) continue;
        for (const o of market.outcomes ?? []) {
          if (o.point === undefined || !o.description) continue;
          // Yardage props are Over/Under — line is symmetric, one side suffices.
          if (o.name !== "Over") continue;
          const key = normalizePlayerName(o.description);
          if (!buckets.has(key)) buckets.set(key, new Map());
          const propMap = buckets.get(key)!;
          if (!propMap.has(market.key)) propMap.set(market.key, []);
          propMap.get(market.key)!.push(o.point);
        }
      }
    }

    if (buckets.size === 0) continue;

    for (const [normKey, propMap] of buckets) {
      const lookup = playerLookup.get(normKey);
      if (!lookup) continue; // unknown player (let fetch-nfl-assets backfill)
      for (const [propType, points] of propMap) {
        const consensus = consensusPoint(points);
        if (consensus === null) continue;
        const { error } = await supabase
          .from("player_game_results")
          .upsert(
            {
              player_espn_id: lookup.espn_id,
              player_name: lookup.player_name,
              team_name: lookup.team_name,
              sport_key: SPORT_KEY,
              game_id: espnGameId,
              game_date: gameDate,
              prop_type: propType,
              line_value: consensus,
            },
            { onConflict: "game_id,player_espn_id,prop_type", ignoreDuplicates: true },
          );
        if (!error) playerInserts++;
      }
    }
  }

  return new Response(
    JSON.stringify({
      success: true,
      games_in_window: dueEvents.length,
      team_rows_inserted: teamInserts,
      player_rows_inserted: playerInserts,
      skipped_no_espn_id: skippedNoEspnId,
    }),
    { headers: { "Content-Type": "application/json" } },
  );
});
