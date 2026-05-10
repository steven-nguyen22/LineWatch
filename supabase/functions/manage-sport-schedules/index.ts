// manage-sport-schedules
//
// Runs once a day. Calls The Odds API's /v4/sports endpoint to discover which
// leagues are currently in-season, then adds or removes pg_cron jobs so the
// 5-minute refreshers only run for active sports.
//
// Triggered by a daily pg_cron entry (see schedule_sport_job / unschedule_sport_job
// RPC helpers and the "manage-sport-schedules" cron job in the database).

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const ODDS_API_KEY = Deno.env.get("ODDS_API_KEY")!;
const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

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

// Fighting (MMA + Boxing) share one odds function.
const FIGHTING_KEYS = ["mma_mixed_martial_arts", "boxing_boxing"];
const FIGHTING_JOB = { jobName: "refresh-fighting", oddsFn: "fetch-fighting-odds" };

// Golf: fetch-golf-odds internally auto-discovers active tournaments; we just
// decide whether the meta-cron for it should be running at all.
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

  // --- discover active sports ---
  const sportsRes = await fetch(
    `https://api.the-odds-api.com/v4/sports?apiKey=${ODDS_API_KEY}`,
  );
  if (!sportsRes.ok) {
    return new Response(
      JSON.stringify({ error: "odds-api-failed", status: sportsRes.status }),
      { status: 502, headers: { "Content-Type": "application/json" } },
    );
  }
  const allSports: Array<{
    key: string;
    group: string;
    active: boolean;
    has_outrights: boolean;
  }> = await sportsRes.json();

  const activeKeys = new Set(allSports.filter((s) => s.active).map((s) => s.key));
  const golfActive = allSports.some((s) => s.group === "Golf" && s.active);

  const decisions: Record<string, { active: boolean; jobs: string[] }> = {};

  // --- per-sport decisions ---
  for (const [sportKey, cfg] of Object.entries(SPORT_MAP)) {
    const active = activeKeys.has(sportKey);
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

    decisions[sportKey] = { active, jobs };
  }

  // --- fighting (combined) ---
  const fightingActive = FIGHTING_KEYS.some((k) => activeKeys.has(k));
  await applyJob(
    supabase,
    `${FIGHTING_JOB.jobName}-odds`,
    FIGHTING_JOB.oddsFn,
    fightingActive,
  );
  decisions["fighting"] = {
    active: fightingActive,
    jobs: [`${FIGHTING_JOB.jobName}-odds`],
  };

  // --- golf ---
  await applyJob(supabase, `${GOLF_JOB.jobName}-odds`, GOLF_JOB.oddsFn, golfActive);
  decisions["golf"] = {
    active: golfActive,
    jobs: [`${GOLF_JOB.jobName}-odds`],
  };

  // --- kalshi (always on; free public API, covers NBA/NFL/MLB/NHL) ---
  await applyJob(supabase, "refresh-kalshi", "fetch-kalshi-odds", true);
  decisions["kalshi"] = { active: true, jobs: ["refresh-kalshi"] };

  return new Response(
    JSON.stringify({ success: true, decisions }, null, 2),
    { headers: { "Content-Type": "application/json" } },
  );
});

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
