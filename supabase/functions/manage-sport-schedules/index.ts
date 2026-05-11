// manage-sport-schedules
//
// Runs once a day. Decides which leagues are currently in-season using a
// calendar-based `SEASON_RANGES` map (mirrors iOS `SportCategory.seasonRange`
// in `LineWatch/Managers/LinesManager.swift`), then adds or removes pg_cron
// jobs so the 5-minute refreshers only run for in-season sports.
//
// Date-based detection replaced the Odds API `/v4/sports` `active` flag
// because the Odds API marks NFL/NBA/etc as `active: true` year-round to
// expose futures markets — which causes the system to keep burning API
// credits refreshing off-season odds nobody can navigate to (off-season
// cards are non-tappable in the iOS UI). Ranges are padded ±14 days to
// absorb preseason matchups and tail-end postseason slippage.
//
// Triggered by a daily pg_cron entry (see schedule_sport_job / unschedule_sport_job
// RPC helpers and the "manage-sport-schedules" cron job in the database).

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

// Season date ranges as [startMonth, startDay, endMonth, endDay].
// MUST be kept in sync with `SportCategory.seasonRange` in
// `LineWatch/Managers/LinesManager.swift`. Sports omitted from this map
// (fighting, golf, kalshi) are year-round.
const SEASON_RANGES: Record<string, [number, number, number, number]> = {
  basketball_nba:            [9, 17, 7, 14], // NBA: Oct 1 – Jun 30 ±14d
  americanfootball_nfl:      [8, 18, 3, 1],  // NFL: Sep 1 – Feb 15 ±14d
  baseball_mlb:              [3, 6, 11, 19], // MLB: Mar 20 – Nov 5 ±14d
  icehockey_nhl:             [9, 17, 7, 14], // NHL: Oct 1 – Jun 30 ±14d
  soccer_uefa_champs_league: [8, 18, 6, 29], // UEFA CL: Sep 1 – Jun 15 ±14d
};

function isInSeason(sportKey: string, now: Date = new Date()): boolean {
  const range = SEASON_RANGES[sportKey];
  if (!range) return true; // year-round
  const [startMonth, startDay, endMonth, endDay] = range;
  const month = now.getUTCMonth() + 1; // getUTCMonth is 0-indexed
  const day = now.getUTCDate();
  const today = month * 100 + day;
  const start = startMonth * 100 + startDay;
  const end = endMonth * 100 + endDay;
  return start <= end
    ? today >= start && today <= end           // doesn't wrap year
    : today >= start || today <= end;          // wraps year (e.g. NFL)
}

// sport_key → { jobName prefix, Edge Function names }
// Job naming convention: "{jobName}-odds" and "{jobName}-props".
const SPORT_MAP: Record<string, { jobName: string; oddsFn: string; propsFn?: string }> = {
  basketball_nba:            { jobName: "refresh-nba",    oddsFn: "fetch-odds",          propsFn: "fetch-player-props" },
  baseball_mlb:              { jobName: "refresh-mlb",    oddsFn: "fetch-baseball-odds", propsFn: "fetch-baseball-player-props" },
  icehockey_nhl:             { jobName: "refresh-nhl",    oddsFn: "fetch-hockey-odds",   propsFn: "fetch-hockey-player-props" },
  americanfootball_nfl:      { jobName: "refresh-nfl",    oddsFn: "fetch-football-odds", propsFn: "fetch-football-player-props" },
  soccer_uefa_champs_league: { jobName: "refresh-soccer", oddsFn: "fetch-soccer-odds",   propsFn: "fetch-soccer-player-props" },
};

// Hit-rate snapshot + post-game grader pairs. Adding a sport is one line
// here plus the corresponding edge-function pair. The orchestration logic
// below activates these jobs only when the sport is in-season.
const HIT_RATE_SPORTS: Record<string, { snapshotFn: string; resultsFn: string }> = {
  basketball_nba:       { snapshotFn: "snapshot-lines-nba", resultsFn: "fetch-nba-game-results" },
  baseball_mlb:         { snapshotFn: "snapshot-lines-mlb", resultsFn: "fetch-mlb-game-results" },
  icehockey_nhl:        { snapshotFn: "snapshot-lines-nhl", resultsFn: "fetch-nhl-game-results" },
  americanfootball_nfl: { snapshotFn: "snapshot-lines-nfl", resultsFn: "fetch-nfl-game-results" },
};

// Fighting (MMA + Boxing) share one odds function. Year-round on iOS.
const FIGHTING_JOB = { jobName: "refresh-fighting", oddsFn: "fetch-fighting-odds" };

// Golf: fetch-golf-odds internally auto-discovers active tournaments via
// its own /v4/sports call. Year-round on iOS.
const GOLF_JOB = { jobName: "refresh-golf", oddsFn: "fetch-golf-odds" };

const SCHEDULE = "*/5 * * * *"; // every 5 minutes

Deno.serve(async (req) => {
  // --- auth: require service_role JWT (same pattern as fetch-odds) ---
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

  const decisions: Record<string, { active: boolean; jobs: string[]; wiped?: boolean }> = {};

  // --- per-sport decisions ---
  for (const [sportKey, cfg] of Object.entries(SPORT_MAP)) {
    const active = isInSeason(sportKey);
    const jobs: string[] = [];

    await applyJob(supabase, `${cfg.jobName}-odds`, cfg.oddsFn, active);
    jobs.push(`${cfg.jobName}-odds`);

    if (cfg.propsFn) {
      await applyJob(supabase, `${cfg.jobName}-props`, cfg.propsFn, active);
      jobs.push(`${cfg.jobName}-props`);
    }

    // Hit-rate snapshot+grader: driven by HIT_RATE_SPORTS map above. NBA + MLB
    // wired up. Each pair is cheap — snapshot is a no-op when no games are in
    // the 25-35 min start window, and the unique constraint makes repeat writes
    // no-ops too. Adding NHL/NFL is just one entry in HIT_RATE_SPORTS plus the
    // corresponding edge-function pair.
    const hitRate = HIT_RATE_SPORTS[sportKey];
    if (hitRate) {
      await applyJob(supabase, `${cfg.jobName}-snapshot`, hitRate.snapshotFn, active);
      if (active) jobs.push(`${cfg.jobName}-snapshot`);

      // Post-game grader: daily at 13:0X UTC (= 9am EDT / 8am EST). All
      // NBA / MLB / NHL / NFL games — even West Coast — are final by then.
      //
      // Staggered minute offsets per sport: avoids 4 graders bursting on
      // ESPN simultaneously, which would be the spike-iest pattern in the
      // whole pipeline. Spread across 15 min instead of <1 min.
      const RESULTS_CRON: Record<string, string> = {
        basketball_nba:       "0 13 * * *",
        baseball_mlb:         "5 13 * * *",
        icehockey_nhl:        "10 13 * * *",
        americanfootball_nfl: "15 13 * * *",
      };
      await applyJob(
        supabase,
        `${cfg.jobName}-results`,
        hitRate.resultsFn,
        active,
        RESULTS_CRON[sportKey] ?? "0 13 * * *",
      );
      if (active) jobs.push(`${cfg.jobName}-results`);
    }

    // When a hit-rate sport goes off-season, wipe its history so the next
    // season starts at zero (no carryover streaks, no last-season-tinged
    // "X of 5" badges). Runs AFTER the snapshot+grader jobs are unscheduled
    // above to avoid racing with an in-flight insert. Idempotent — once
    // empty, future daily runs delete 0 rows.
    let wiped = false;
    if (hitRate && !active) {
      await wipeHitRatesForSport(supabase, sportKey);
      wiped = true;
    }

    decisions[sportKey] = { active, jobs, wiped };
  }

  // --- fighting (combined) ---
  // Year-round on iOS — always scheduled. fetch-fighting-odds gracefully
  // returns an empty list when no MMA/boxing events are upcoming.
  await applyJob(
    supabase,
    `${FIGHTING_JOB.jobName}-odds`,
    FIGHTING_JOB.oddsFn,
    true,
  );
  decisions["fighting"] = {
    active: true,
    jobs: [`${FIGHTING_JOB.jobName}-odds`],
  };

  // --- golf ---
  // Year-round on iOS — always scheduled. fetch-golf-odds self-discovers
  // active tournaments via its own /v4/sports call and no-ops when none.
  await applyJob(supabase, `${GOLF_JOB.jobName}-odds`, GOLF_JOB.oddsFn, true);
  decisions["golf"] = {
    active: true,
    jobs: [`${GOLF_JOB.jobName}-odds`],
  };

  // --- kalshi (always on; free public API, covers NBA/NFL/MLB/NHL) ---
  await applyJob(supabase, "refresh-kalshi", "fetch-kalshi-odds", true);
  decisions["kalshi"] = { active: true, jobs: ["refresh-kalshi"] };

  // --- hot streaks (single daily aggregate, not per-sport) ---
  // Run at 13:30 UTC, after the 4 graders finish (NBA 13:00, MLB 13:05,
  // NHL 13:10, NFL 13:15). Always-on — the function itself skips sports
  // with no graded rows.
  await applyJob(
    supabase,
    "compute-hot-streaks",
    "compute-hot-streaks",
    true,
    "30 13 * * *",
  );
  decisions["hot_streaks"] = { active: true, jobs: ["compute-hot-streaks"] };

  return new Response(
    JSON.stringify({ success: true, decisions }, null, 2),
    { headers: { "Content-Type": "application/json" } },
  );
});

// Delete all hit-rates history for a sport. Called once per off-season
// transition (and harmlessly each subsequent off-season day — once empty,
// the DELETEs match 0 rows).
//
// IMPORTANT: callers must unschedule the sport's snapshot + grader cron
// jobs BEFORE invoking this, so a still-running job can't re-insert a row
// during the wipe. The date-based `isInSeason()` check is the trigger —
// see the `if (hitRate && !active)` guard at the call site.
//
// hot_streaks / cold_streaks are technically redundant — the daily
// 13:30 compute would clear the off-season sport's rows within ~24h
// since there are no graded candidates left — but doing it inline
// closes the UI gap where stale streaks would still appear on the iOS
// Streaks page (both tabs) until the next compute run.
async function wipeHitRatesForSport(
  supabase: ReturnType<typeof createClient>,
  sportKey: string,
) {
  const tables = ["player_game_results", "team_game_results", "hot_streaks", "cold_streaks"];
  for (const table of tables) {
    const { error, count } = await supabase
      .from(table)
      .delete({ count: "exact" })
      .eq("sport_key", sportKey);
    if (error) {
      console.error(`wipe ${table} for ${sportKey} failed:`, error);
    } else {
      console.log(`wiped ${count ?? 0} rows from ${table} for ${sportKey}`);
    }
  }
}

async function applyJob(
  supabase: ReturnType<typeof createClient>,
  jobName: string,
  fnName: string,
  active: boolean,
  cron: string = SCHEDULE,
) {
  if (active) {
    const { error } = await supabase.rpc("schedule_sport_job", {
      p_job_name: jobName,
      p_fn_name: fnName,
      p_cron: cron,
    });
    if (error) console.error(`schedule ${jobName} failed:`, error);
  } else {
    const { error } = await supabase.rpc("unschedule_sport_job", {
      p_job_name: jobName,
    });
    if (error) console.error(`unschedule ${jobName} failed:`, error);
  }
}
