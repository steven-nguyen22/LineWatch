// fetch-nhl-game-results
//
// Daily post-game ingestion for NHL. Pulls yesterday's NHL scoreboard from
// ESPN and UPDATEs the pending rows that snapshot-lines-nhl wrote at game
// start time. Team-only V1 — no player-prop grading yet.
//
// We only UPDATE rows already snapshotted — never INSERT. If a snapshot
// was missed (e.g. cron downtime), that game just doesn't get a hit-rate
// entry. This keeps the data clean: every row has a known closing line.
//
// Margin / spread cover:
//   actual_margin = team_score - opponent_score (positive = won by N)
//   covered = (actual_margin + spread_line) > 0
//   (spread_line is negative when favored — e.g. -1.5 means win by 2+ covers)
//
// OT / Shootout: ESPN scoreboard reports the final result with the SO winner's
// score boosted by exactly 1 (NHL convention), so margin = ±1 for any SO
// game. The same `(actual_margin + spread_line) > 0` formula correctly
// grades a -1.5 favorite as not covering on an SO win, and a +1.5 underdog
// as covering on an SO loss — matching how books grade the puck line.
//
// Why we don't need the box-score `summary` endpoint here: team-only grading
// only requires final scores, which are already on the scoreboard event under
// `competitions[0].competitors[].score`. One ESPN call per day grades every
// NHL game from the previous night.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

const SPORT_KEY = "icehockey_nhl";

interface ESPNCompetitor {
  team?: { id?: string; displayName?: string };
  score?: string;
  homeAway?: string;
}

interface ESPNScoreboardEvent {
  id: string;
  status?: { type?: { completed?: boolean } };
  competitions?: Array<{ competitors?: ESPNCompetitor[] }>;
}

/** YYYYMMDD for "yesterday" in ET — the ESPN scoreboard query format. */
function yesterdayETDate(): string {
  // ET is UTC-5 (EST) or UTC-4 (EDT). For a daily 9am-ET cron, "yesterday"
  // in ET reliably corresponds to (now - 24h) in UTC, then stripped to date.
  const now = new Date();
  const yesterday = new Date(now.getTime() - 24 * 3600_000);
  // Pull ET date components by shifting to UTC-4 (DST-safe enough — cron
  // always runs after all NHL games are final, even West Coast late games).
  const etShifted = new Date(yesterday.getTime() - 4 * 3600_000);
  const yyyy = etShifted.getUTCFullYear();
  const mm = String(etShifted.getUTCMonth() + 1).padStart(2, "0");
  const dd = String(etShifted.getUTCDate()).padStart(2, "0");
  return `${yyyy}${mm}${dd}`;
}

Deno.serve(async (req) => {
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

  // ---------------------------------------------------------------------------
  // 1. ESPN scoreboard for yesterday — find completed games
  // ---------------------------------------------------------------------------
  const dateStr = yesterdayETDate();
  const scoreboardUrl =
    `https://site.api.espn.com/apis/site/v2/sports/hockey/nhl/scoreboard?dates=${dateStr}`;
  const sbRes = await fetch(scoreboardUrl);
  if (!sbRes.ok) {
    return new Response(
      JSON.stringify({ error: "espn-scoreboard-failed", status: sbRes.status }),
      { status: 502, headers: { "Content-Type": "application/json" } },
    );
  }
  const sbBody = await sbRes.json();
  const events: ESPNScoreboardEvent[] = sbBody?.events ?? [];
  const completed = events.filter((e) => e.status?.type?.completed === true);

  if (completed.length === 0) {
    return new Response(
      JSON.stringify({
        success: true,
        date: dateStr,
        games_completed: 0,
        team_rows_updated: 0,
      }),
      { headers: { "Content-Type": "application/json" } },
    );
  }

  // ---------------------------------------------------------------------------
  // 2. For each completed game: read final scores from the scoreboard event
  //    and grade the snapshotted rows.
  // ---------------------------------------------------------------------------
  let teamRowsUpdated = 0;
  const errors: string[] = [];

  for (const event of completed) {
    try {
      const competitors: ESPNCompetitor[] = event.competitions?.[0]?.competitors ?? [];
      if (competitors.length !== 2) continue;

      const [a, b] = competitors;
      const aId = parseInt(a.team?.id ?? "0", 10);
      const bId = parseInt(b.team?.id ?? "0", 10);
      const aScore = parseInt(a.score ?? "0", 10);
      const bScore = parseInt(b.score ?? "0", 10);

      for (const [teamEspnId, ownScore, oppScore] of [
        [aId, aScore, bScore],
        [bId, bScore, aScore],
      ] as const) {
        if (!teamEspnId) continue;
        const margin = ownScore - oppScore;

        // Look up the pending row (spread_line was snapshotted earlier)
        const { data: pending } = await supabase
          .from("team_game_results")
          .select("id, spread_line")
          .eq("game_id", event.id)
          .eq("team_espn_id", teamEspnId)
          .eq("sport_key", SPORT_KEY)
          .maybeSingle();

        if (!pending) continue; // never snapshotted — skip silently
        const covered = margin + Number(pending.spread_line) > 0;
        const { error } = await supabase
          .from("team_game_results")
          .update({ actual_margin: margin, covered })
          .eq("id", pending.id);
        if (!error) teamRowsUpdated++;
      }
    } catch (err) {
      errors.push(`${event.id}: ${err instanceof Error ? err.message : String(err)}`);
    }
  }

  return new Response(
    JSON.stringify({
      success: true,
      date: dateStr,
      games_completed: completed.length,
      team_rows_updated: teamRowsUpdated,
      errors,
    }),
    { headers: { "Content-Type": "application/json" } },
  );
});
