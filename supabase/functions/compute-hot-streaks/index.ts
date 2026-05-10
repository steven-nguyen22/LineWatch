// compute-hot-streaks
//
// Daily aggregate that computes the top 3 hottest streaks per in-season
// sport across team wins, team spreads, and player props. Powers the
// iOS Hot Streaks discovery surface.
//
// Schedule: 13:30 UTC, after the four graders finish (NBA 13:00, MLB
// 13:05, NHL 13:10, NFL 13:15). Registered via manage-sport-schedules.
//
// Data sources (already populated by the existing graders):
//   team_game_results   — actual_margin, covered, game_date per team-game
//   player_game_results — hit, game_date per player-prop-game
//
// Streak walk mirrors HitRateHistoryGrid.streakParts() in Swift: sort
// newest-first, count consecutive matches at the head until the first
// miss. Hot only — we ignore cold streaks here (the iOS feature is
// titled "Hot Streaks", not "Streaks").
//
// Output: ≤3 rows per sport in the `hot_streaks` table. Replacement is
// per-sport delete+insert (Supabase JS client has no transaction API;
// the brief gap is acceptable for a discovery surface).
//
// No minimum streak threshold — even streaks of 1 qualify. In practice,
// once each sport has a few graded games, streaks ≥3 dominate the top.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

const SPORTS = [
  "basketball_nba",
  "baseball_mlb",
  "icehockey_nhl",
  "americanfootball_nfl",
];

// Maps prop_type → human-readable label. Used to format the `description`
// column shown in the iOS card subtitle, e.g. "Points Over 25.5".
const PROP_LABELS: Record<string, string> = {
  player_points:        "Points",
  player_rebounds:      "Rebounds",
  player_assists:       "Assists",
  batter_hits:          "Hits",
  batter_home_runs:     "Home Runs",
  pitcher_strikeouts:   "Strikeouts",
  player_goals:         "Goals",
  player_shots_on_goal: "Shots on Goal",
  hockey_player_points: "Points",
  player_pass_yds:      "Passing Yards",
  player_rush_yds:      "Rushing Yards",
  player_reception_yds: "Receiving Yards",
};

interface TeamRow {
  team_espn_id: number;
  team_name: string;
  game_date: string;
  covered: boolean | null;
  actual_margin: number | null;
}

interface PlayerRow {
  player_espn_id: number;
  player_name: string;
  team_name: string | null;
  prop_type: string;
  game_date: string;
  hit: boolean | null;
}

// Candidate streak entry — pre-ranking. Mixes wins/spread/prop into one
// shape so we can sort them all together and slice the top 3.
interface Candidate {
  streak_type: string;            // 'wins' | 'spread' | <prop_type>
  streak_count: number;
  last_game_date: string;
  // Identity. For team streaks (wins/spread): team_* set, player_* nil.
  // For player streaks: player_* set, plus team_name (the player's team)
  // is also populated so the iOS tap-through can find the player's next
  // upcoming game.
  team_espn_id?: number;
  team_name?: string;
  player_espn_id?: number;
  player_name?: string;
  // Tiebreaker: stable order across runs.
  espn_id_for_sort: number;
}

/**
 * Walk a sorted-newest-first array and count consecutive entries where
 * `predicate(entry) === true` at the head. Stops at first miss. Returns
 * 0 if the head doesn't satisfy the predicate.
 *
 * Mirrors HitRateHistoryGrid.streakParts() in Swift exactly (4-line core).
 */
function hotStreakLength<T>(rows: T[], predicate: (row: T) => boolean): number {
  let count = 0;
  for (const r of rows) {
    if (!predicate(r)) break;
    count++;
  }
  return count;
}

/**
 * Group an array by a key function — newest-first ordering preserved
 * within each group as long as the input is sorted newest-first.
 */
function groupBy<T>(rows: T[], keyFn: (row: T) => string): Map<string, T[]> {
  const out = new Map<string, T[]>();
  for (const r of rows) {
    const k = keyFn(r);
    if (!out.has(k)) out.set(k, []);
    out.get(k)!.push(r);
  }
  return out;
}

/**
 * Returns the human-readable prop name only — no "Over X.X" suffix.
 * The streak count is the headline number on the card; the closing line
 * isn't relevant to a discovery surface, so we keep the description tight.
 */
function describeProp(propType: string): string {
  return PROP_LABELS[propType] ?? propType;
}

async function computeForSport(
  // deno-lint-ignore no-explicit-any
  supabase: any,
  sportKey: string,
): Promise<{ sport: string; rows_written: number; candidates_total: number }> {
  // ---- 1. Pull all graded team rows for this sport ----
  const { data: teamRowsRaw, error: teamErr } = await supabase
    .from("team_game_results")
    .select("team_espn_id, team_name, game_date, covered, actual_margin")
    .eq("sport_key", sportKey)
    .not("covered", "is", null)
    .order("game_date", { ascending: false });

  if (teamErr) throw new Error(`team fetch ${sportKey}: ${teamErr.message}`);
  const teamRows: TeamRow[] = teamRowsRaw ?? [];

  // ---- 2. Pull all graded player rows for this sport ----
  const { data: playerRowsRaw, error: playerErr } = await supabase
    .from("player_game_results")
    .select("player_espn_id, player_name, team_name, prop_type, game_date, hit")
    .eq("sport_key", sportKey)
    .not("hit", "is", null)
    .order("game_date", { ascending: false });

  if (playerErr) throw new Error(`player fetch ${sportKey}: ${playerErr.message}`);
  const playerRows: PlayerRow[] = playerRowsRaw ?? [];

  // ---- 3. Build candidate list ----
  const candidates: Candidate[] = [];

  // Wins streaks (per team, newest-first while actual_margin > 0).
  const teamsByEspnId = groupBy(teamRows, (r) => String(r.team_espn_id));
  for (const [, rows] of teamsByEspnId) {
    if (rows.length === 0) continue;
    const winsLen = hotStreakLength(rows, (r) => (r.actual_margin ?? 0) > 0);
    if (winsLen > 0) {
      candidates.push({
        streak_type: "wins",
        streak_count: winsLen,
        last_game_date: rows[0].game_date,
        team_espn_id: rows[0].team_espn_id,
        team_name: rows[0].team_name,
        espn_id_for_sort: rows[0].team_espn_id,
      });
    }
    const spreadLen = hotStreakLength(rows, (r) => r.covered === true);
    if (spreadLen > 0) {
      candidates.push({
        streak_type: "spread",
        streak_count: spreadLen,
        last_game_date: rows[0].game_date,
        team_espn_id: rows[0].team_espn_id,
        team_name: rows[0].team_name,
        espn_id_for_sort: rows[0].team_espn_id,
      });
    }
  }

  // Prop streaks (per player+prop_type, newest-first while hit === true).
  const propGroups = groupBy(
    playerRows,
    (r) => `${r.player_espn_id}|${r.prop_type}`,
  );
  for (const [, rows] of propGroups) {
    if (rows.length === 0) continue;
    const len = hotStreakLength(rows, (r) => r.hit === true);
    if (len > 0) {
      candidates.push({
        streak_type: rows[0].prop_type,
        streak_count: len,
        last_game_date: rows[0].game_date,
        player_espn_id: rows[0].player_espn_id,
        player_name: rows[0].player_name,
        // Player's team — populated so the iOS Hot Streaks tap-through
        // can resolve the player's next upcoming game without needing
        // `playerTeamsByEvent` to be pre-loaded for the sport.
        team_name: rows[0].team_name ?? undefined,
        espn_id_for_sort: rows[0].player_espn_id,
      });
    }
  }

  // ---- 4. Sort + take top 3 ----
  // Primary: streak_count desc. Tiebreaker 1: last_game_date desc (more
  // recent = "hotter"). Tiebreaker 2: espn_id asc for stable ordering.
  candidates.sort((a, b) => {
    if (b.streak_count !== a.streak_count) return b.streak_count - a.streak_count;
    if (b.last_game_date !== a.last_game_date) {
      return b.last_game_date.localeCompare(a.last_game_date);
    }
    return a.espn_id_for_sort - b.espn_id_for_sort;
  });

  const top3 = candidates.slice(0, 3);

  // ---- 5. Format rows for insertion ----
  const rowsToInsert = top3.map((c, idx) => {
    const isPlayer = c.player_espn_id !== undefined;
    const displayName = isPlayer ? c.player_name! : c.team_name!;
    let description: string;
    if (c.streak_type === "wins") description = "Wins";
    else if (c.streak_type === "spread") description = "Spread";
    else description = describeProp(c.streak_type);

    return {
      sport_key: sportKey,
      rank: idx + 1,
      streak_count: c.streak_count,
      streak_type: c.streak_type,
      team_espn_id: c.team_espn_id ?? null,
      team_name: c.team_name ?? null,
      player_espn_id: c.player_espn_id ?? null,
      player_name: c.player_name ?? null,
      display_name: displayName,
      description,
      last_game_date: c.last_game_date,
    };
  });

  // ---- 6. Atomic-ish replace for this sport ----
  // Sequential delete+insert. Brief gap acceptable for discovery surface.
  const { error: delErr } = await supabase
    .from("hot_streaks")
    .delete()
    .eq("sport_key", sportKey);
  if (delErr) throw new Error(`delete ${sportKey}: ${delErr.message}`);

  if (rowsToInsert.length > 0) {
    const { error: insErr } = await supabase
      .from("hot_streaks")
      .insert(rowsToInsert);
    if (insErr) throw new Error(`insert ${sportKey}: ${insErr.message}`);
  }

  return {
    sport: sportKey,
    rows_written: rowsToInsert.length,
    candidates_total: candidates.length,
  };
}

Deno.serve(async (req) => {
  // service-role JWT gate (same pattern as every other edge fn)
  const auth = req.headers.get("authorization") ?? "";
  const token = auth.replace(/^Bearer\s+/i, "");
  try {
    const [, payloadB64] = token.split(".");
    const payload = JSON.parse(
      atob(payloadB64.replace(/-/g, "+").replace(/_/g, "/")),
    );
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

  const results: Array<{ sport: string; rows_written: number; candidates_total: number }> = [];
  const errors: string[] = [];

  for (const sportKey of SPORTS) {
    try {
      const r = await computeForSport(supabase, sportKey);
      results.push(r);
    } catch (err) {
      errors.push(`${sportKey}: ${err instanceof Error ? err.message : String(err)}`);
    }
  }

  const totalRows = results.reduce((s, r) => s + r.rows_written, 0);

  return new Response(
    JSON.stringify({
      success: errors.length === 0,
      sports_processed: results.length,
      rows_written: totalRows,
      results,
      errors,
    }, null, 2),
    { headers: { "Content-Type": "application/json" } },
  );
});
