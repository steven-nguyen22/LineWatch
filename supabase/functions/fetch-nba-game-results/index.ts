// fetch-nba-game-results
//
// Daily post-game ingestion. Pulls yesterday's NBA scoreboard from ESPN,
// walks each completed game's box score, and UPDATEs the pending rows
// that snapshot-lines-nba wrote at game-start time.
//
// We only UPDATE rows already snapshotted — never INSERT. If a snapshot
// was missed (e.g. cron downtime), that game just doesn't get a hit-rate
// entry. This keeps the data clean: every row has a known closing line.
//
// Stat parsing — verified against ESPN's response shape:
//   boxscore.players[].statistics[0].keys[] gives the column labels
//   athletes[].stats[] is positional and lines up with .keys[]
//   For NBA: points=index 1, rebounds=index 5, assists=index 6
//
// Margin / spread cover:
//   actual_margin = team_score - opponent_score (positive = won by N)
//   covered = (actual_margin + spread_line) > 0
//   (spread_line is negative when favored; e.g. -3.5 means win by 4+ covers)

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

const SPORT_KEY = "basketball_nba";

// ESPN box-score stat array indices for NBA (verified against live API)
const STAT_INDEX: Record<string, number> = {
  player_points: 1,
  player_rebounds: 5,
  player_assists: 6,
};

interface ESPNScoreboardEvent {
  id: string;
  status?: { type?: { completed?: boolean } };
}

interface ESPNCompetitor {
  team?: { id?: string; displayName?: string };
  score?: string;
  homeAway?: string;
}

interface ESPNBoxAthlete {
  athlete?: { id?: string; displayName?: string };
  stats?: string[];
  didNotPlay?: boolean;
}

interface ESPNBoxTeam {
  team?: { id?: string; displayName?: string };
  statistics?: Array<{ keys?: string[]; athletes?: ESPNBoxAthlete[] }>;
}

/** YYYYMMDD for "yesterday" in ET — the ESPN scoreboard query format. */
function yesterdayETDate(): string {
  // ET is UTC-5 (EST) or UTC-4 (EDT). For a daily 8am-ET cron, "yesterday"
  // in ET reliably corresponds to (now - 24h) in UTC, then stripped to date.
  const now = new Date();
  const yesterday = new Date(now.getTime() - 24 * 3600_000);
  // Pull ET date components by shifting to UTC-4 (DST-safe enough for our
  // window — cron always runs after all NBA games are final, even West Coast).
  const etShifted = new Date(yesterday.getTime() - 4 * 3600_000);
  const yyyy = etShifted.getUTCFullYear();
  const mm = String(etShifted.getUTCMonth() + 1).padStart(2, "0");
  const dd = String(etShifted.getUTCDate()).padStart(2, "0");
  return `${yyyy}${mm}${dd}`;
}

/** Parse a stat string. ESPN sometimes returns "—" for DNP entries. */
function parseStat(raw: string | undefined): number | null {
  if (!raw) return null;
  const n = parseFloat(raw);
  return Number.isFinite(n) ? n : null;
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
    `https://site.api.espn.com/apis/site/v2/sports/basketball/nba/scoreboard?dates=${dateStr}`;
  const sbRes = await fetch(scoreboardUrl);
  if (!sbRes.ok) {
    return new Response(
      JSON.stringify({ error: "espn-scoreboard-failed", status: sbRes.status }),
      { status: 502, headers: { "Content-Type": "application/json" } },
    );
  }
  const sbBody = await sbRes.json();
  const events: ESPNScoreboardEvent[] = sbBody?.events ?? [];
  const completedIds = events
    .filter((e) => e.status?.type?.completed === true)
    .map((e) => e.id);

  if (completedIds.length === 0) {
    return new Response(
      JSON.stringify({
        success: true,
        date: dateStr,
        games_completed: 0,
        player_rows_updated: 0,
        team_rows_updated: 0,
      }),
      { headers: { "Content-Type": "application/json" } },
    );
  }

  let playerRowsUpdated = 0;
  let teamRowsUpdated = 0;
  const errors: string[] = [];

  // ---------------------------------------------------------------------------
  // 2. For each completed game: pull box score, write player + team results
  // ---------------------------------------------------------------------------
  for (const gameId of completedIds) {
    try {
      const summaryUrl =
        `https://site.api.espn.com/apis/site/v2/sports/basketball/nba/summary?event=${gameId}`;
      const sumRes = await fetch(summaryUrl);
      if (!sumRes.ok) {
        errors.push(`summary ${gameId}: HTTP ${sumRes.status}`);
        continue;
      }
      const summary = await sumRes.json();

      // ---- TEAM RESULTS (final scores → margin → covered) -------------------
      const competitors: ESPNCompetitor[] =
        summary?.header?.competitions?.[0]?.competitors ?? [];
      if (competitors.length === 2) {
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
            .eq("game_id", gameId)
            .eq("team_espn_id", teamEspnId)
            .maybeSingle();

          if (!pending) continue; // never snapshotted — skip silently
          const covered = margin + Number(pending.spread_line) > 0;
          const { error } = await supabase
            .from("team_game_results")
            .update({ actual_margin: margin, covered })
            .eq("id", pending.id);
          if (!error) teamRowsUpdated++;
        }
      }

      // ---- PLAYER RESULTS (per-athlete stats) -------------------------------
      const boxTeams: ESPNBoxTeam[] = summary?.boxscore?.players ?? [];
      for (const team of boxTeams) {
        const statgroup = team.statistics?.[0];
        if (!statgroup) continue;
        const keys = statgroup.keys ?? [];
        for (const a of statgroup.athletes ?? []) {
          if (a.didNotPlay) continue;
          const athleteId = parseInt(a.athlete?.id ?? "0", 10);
          if (!athleteId) continue;

          for (const propType of Object.keys(STAT_INDEX)) {
            const idx = STAT_INDEX[propType];
            // Defensive: confirm the key at this index matches what we expect.
            // ESPN occasionally reorders keys — bail on this prop if so rather
            // than writing a wrong stat.
            const expectedKey = propType.replace("player_", "");
            if (keys[idx] && keys[idx] !== expectedKey) continue;

            const actual = parseStat(a.stats?.[idx]);
            if (actual === null) continue;

            const { data: pending } = await supabase
              .from("player_game_results")
              .select("id, line_value")
              .eq("game_id", gameId)
              .eq("player_espn_id", athleteId)
              .eq("prop_type", propType)
              .maybeSingle();

            if (!pending) continue; // not snapshotted — skip
            const hit = actual >= Number(pending.line_value);
            const { error } = await supabase
              .from("player_game_results")
              .update({ actual_value: actual, hit })
              .eq("id", pending.id);
            if (!error) playerRowsUpdated++;
          }
        }
      }
    } catch (err) {
      errors.push(`${gameId}: ${err instanceof Error ? err.message : String(err)}`);
    }
  }

  return new Response(
    JSON.stringify({
      success: true,
      date: dateStr,
      games_completed: completedIds.length,
      player_rows_updated: playerRowsUpdated,
      team_rows_updated: teamRowsUpdated,
      errors,
    }),
    { headers: { "Content-Type": "application/json" } },
  );
});
