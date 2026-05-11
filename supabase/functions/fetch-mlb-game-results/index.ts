// fetch-mlb-game-results
//
// Daily post-game ingestion for MLB. Pulls yesterday's MLB scoreboard from
// ESPN and UPDATEs the pending rows that snapshot-lines-mlb wrote at game
// start time — both team spreads and player props (batter hits, batter
// home runs, pitcher strikeouts).
//
// We only UPDATE rows already snapshotted — never INSERT. If a snapshot
// was missed (e.g. cron downtime), that game just doesn't get a hit-rate
// entry. This keeps the data clean: every row has a known closing line.
//
// Margin / spread cover (team rows):
//   actual_margin = team_score - opponent_score (positive = won by N)
//   covered = (actual_margin + spread_line) > 0
//   (spread_line is negative when favored — e.g. -1.5 means win by 2+ covers)
//
// Box-score parsing for player props:
//   For each completed game we hit ESPN's `summary` endpoint and walk
//   `boxscore.players[].statistics[]`. MLB groups stats by category — we
//   look for `statistics.name === "batting"` (H, HR) and `"pitching"` (K).
//   Stat-key indices are discovered defensively from the `keys[]` array
//   per response, since ESPN occasionally reorders columns.

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


const SPORT_KEY = "baseball_mlb";

// Maps prop_type → { ESPN box-score group name, ESPN key label }.
// `group` matches `boxscore.players[].statistics[].name`. `key` is the
// label inside that group's `keys[]` array (positional alongside `stats[]`).
const PLAYER_STAT_MAP: Record<string, { group: string; key: string }> = {
  batter_hits:        { group: "batting",  key: "H" },
  batter_home_runs:   { group: "batting",  key: "HR" },
  pitcher_strikeouts: { group: "pitching", key: "K" },
};

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

interface ESPNBoxAthlete {
  athlete?: { id?: string; displayName?: string };
  stats?: string[];
  active?: boolean;
}

interface ESPNBoxStatGroup {
  name?: string;
  keys?: string[];
  athletes?: ESPNBoxAthlete[];
}

interface ESPNBoxTeam {
  team?: { id?: string; displayName?: string };
  statistics?: ESPNBoxStatGroup[];
}

/** YYYYMMDD for "yesterday" in ET — the ESPN scoreboard query format. */
function yesterdayETDate(): string {
  // ET is UTC-5 (EST) or UTC-4 (EDT). For a daily 9am-ET cron, "yesterday"
  // in ET reliably corresponds to (now - 24h) in UTC, then stripped to date.
  const now = new Date();
  const yesterday = new Date(now.getTime() - 24 * 3600_000);
  // Pull ET date components by shifting to UTC-4 (DST-safe enough — cron
  // always runs after all MLB games are final, even West Coast late nights).
  const etShifted = new Date(yesterday.getTime() - 4 * 3600_000);
  const yyyy = etShifted.getUTCFullYear();
  const mm = String(etShifted.getUTCMonth() + 1).padStart(2, "0");
  const dd = String(etShifted.getUTCDate()).padStart(2, "0");
  return `${yyyy}${mm}${dd}`;
}

/** Parse a stat string. ESPN returns "—" or empty for missing/DNP entries. */
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
    `https://site.api.espn.com/apis/site/v2/sports/baseball/mlb/scoreboard?dates=${dateStr}`;
  const sbRes = await espnFetch(scoreboardUrl, supabase, "fetch-mlb-game-results");
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
        player_rows_updated: 0,
      }),
      { headers: { "Content-Type": "application/json" } },
    );
  }

  // ---------------------------------------------------------------------------
  // 2. For each completed game: grade team spreads + player props.
  // ---------------------------------------------------------------------------
  let teamRowsUpdated = 0;
  let playerRowsUpdated = 0;
  const errors: string[] = [];

  // Bulk-load all pending player_game_results rows for the day's games.
  // Replaces per-athlete SELECTs inside the box-score loop — one query
  // here vs ~hundreds of round-trips. Map keyed by `${event.id}|${player}|${prop}`.
  const completedIds = completed.map((e) => e.id);
  // Pull all NOT-NULL columns alongside id/line_value — the bulk upsert at
  // the bottom of this function needs to round-trip them. PostgREST's upsert
  // evaluates NOT-NULL on the INSERT path of `INSERT ... ON CONFLICT DO UPDATE`
  // even when every row conflicts, so a partial payload silently errors out.
  const { data: pendingPlayerRows } = await supabase
    .from("player_game_results")
    .select("id, game_id, player_espn_id, prop_type, line_value, player_name, team_name, game_date")
    .in("game_id", completedIds)
    .eq("sport_key", SPORT_KEY)
    .is("actual_value", null);

  const pendingByKey = new Map<string, {
    id: string;
    line_value: number;
    player_name: string;
    team_name: string;
    game_date: string;
  }>();
  for (const r of pendingPlayerRows ?? []) {
    pendingByKey.set(
      `${r.game_id}|${r.player_espn_id}|${r.prop_type}`,
      {
        id: r.id,
        line_value: r.line_value,
        player_name: r.player_name,
        team_name: r.team_name,
        game_date: r.game_date,
      },
    );
  }

  // Accumulate updates across all games — flush in one bulk upsert at the end.
  const playerUpdates: Array<{
    id: string;
    player_espn_id: number;
    player_name: string;
    team_name: string;
    sport_key: string;
    game_id: string;
    game_date: string;
    prop_type: string;
    line_value: number;
    actual_value: number;
    hit: boolean;
  }> = [];

  for (const event of completed) {
    try {
      // ---- TEAM RESULTS (final scores → margin → covered) ------------------
      const competitors: ESPNCompetitor[] = event.competitions?.[0]?.competitors ?? [];
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
      }

      // ---- PLAYER RESULTS (per-athlete batting + pitching stats) -----------
      // MLB box-score has separate "batting" and "pitching" groups per team.
      // We pull the full summary once and let each prop type's mapping
      // direct us to the right group + key.
      const summaryUrl =
        `https://site.api.espn.com/apis/site/v2/sports/baseball/mlb/summary?event=${event.id}`;
      const sumRes = await espnFetch(summaryUrl, supabase, "fetch-mlb-game-results");
      if (!sumRes.ok) {
        errors.push(`summary ${event.id}: HTTP ${sumRes.status}`);
        continue;
      }
      const summary = await sumRes.json();
      const boxTeams: ESPNBoxTeam[] = summary?.boxscore?.players ?? [];

      for (const team of boxTeams) {
        for (const statgroup of team.statistics ?? []) {
          const groupName = statgroup.name;
          if (!groupName) continue;
          const keys = statgroup.keys ?? [];

          // Find every prop_type whose mapping targets this group; each one
          // gets its own column index inside this group's `keys[]` array.
          const propsForGroup = Object.entries(PLAYER_STAT_MAP)
            .filter(([, m]) => m.group === groupName)
            .map(([propType, m]) => ({ propType, idx: keys.indexOf(m.key) }))
            .filter(({ idx }) => idx >= 0);
          if (propsForGroup.length === 0) continue;

          for (const a of statgroup.athletes ?? []) {
            const athleteId = parseInt(a.athlete?.id ?? "0", 10);
            if (!athleteId) continue;

            for (const { propType, idx } of propsForGroup) {
              const actual = parseStat(a.stats?.[idx]);
              if (actual === null) continue;

              const pending = pendingByKey.get(`${event.id}|${athleteId}|${propType}`);
              if (!pending) continue; // not snapshotted — skip
              const hit = actual >= Number(pending.line_value);
              playerUpdates.push({
                id: pending.id,
                player_espn_id: athleteId,
                player_name: pending.player_name,
                team_name: pending.team_name,
                sport_key: SPORT_KEY,
                game_id: event.id,
                game_date: pending.game_date,
                prop_type: propType,
                line_value: pending.line_value,
                actual_value: actual,
                hit,
              });
              playerRowsUpdated++;
            }
          }
        }
      }
    } catch (err) {
      errors.push(`${event.id}: ${err instanceof Error ? err.message : String(err)}`);
    }
  }

  // 3. Flush all accumulated player updates in a single bulk upsert.
  if (playerUpdates.length > 0) {
    const { error: bulkErr } = await supabase
      .from("player_game_results")
      .upsert(playerUpdates, { onConflict: "id" });
    if (bulkErr) {
      errors.push(`bulk player upsert: ${bulkErr.message}`);
      playerRowsUpdated = 0;
    }
  }

  return new Response(
    JSON.stringify({
      success: true,
      date: dateStr,
      games_completed: completed.length,
      team_rows_updated: teamRowsUpdated,
      player_rows_updated: playerRowsUpdated,
      errors,
    }),
    { headers: { "Content-Type": "application/json" } },
  );
});
