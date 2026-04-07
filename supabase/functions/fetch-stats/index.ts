import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

function sleep(ms: number): Promise<void> {
  return new Promise((r) => setTimeout(r, ms));
}

// ─── Sport Configuration ─────────────────────────────────────────────

interface SeasonRange {
  startMonth: number;
  startDay: number;
  endMonth: number;
  endDay: number;
}

interface SportConfig {
  sportKey: string;
  espnSport: string; // e.g., "basketball/nba"
  espnLeague: string; // e.g., "nba"
  playerTables: string[]; // e.g., ["nba_players"] or ["nfl_qbs", "nfl_rbs", "nfl_receivers"]
  formatTeamStats: (entry: any) => Record<string, string>;
  formatPlayerStats: (data: any, position?: string) => Record<string, string>;
  /** Date range when this sport is in season. null = year-round. */
  seasonRange: SeasonRange | null;
}

/** Mirrors the iOS `isInSeason` logic in LinesManager.swift. */
function isInSeason(config: SportConfig): boolean {
  if (!config.seasonRange) return true;
  const now = new Date();
  const m = now.getUTCMonth() + 1; // 1–12
  const d = now.getUTCDate();
  const today = m * 100 + d; // e.g. Apr 6 = 406, Oct 1 = 1001
  const { startMonth, startDay, endMonth, endDay } = config.seasonRange;
  const start = startMonth * 100 + startDay;
  const end = endMonth * 100 + endDay;
  if (start <= end) {
    // Season doesn't wrap the year (e.g. MLB Mar–Nov)
    return today >= start && today <= end;
  }
  // Season wraps the year (e.g. NBA Oct–Jun, NFL Sep–Feb)
  return today >= start || today <= end;
}

const SPORT_CONFIGS: SportConfig[] = [
  {
    sportKey: "basketball_nba",
    espnSport: "basketball/nba",
    espnLeague: "nba",
    playerTables: ["nba_players"],
    formatTeamStats: formatNBATeamStats,
    formatPlayerStats: formatNBAPlayerStats,
    seasonRange: { startMonth: 10, startDay: 1, endMonth: 6, endDay: 30 }, // Oct 1 – Jun 30
  },
  {
    sportKey: "baseball_mlb",
    espnSport: "baseball/mlb",
    espnLeague: "mlb",
    playerTables: ["mlb_players"],
    formatTeamStats: formatMLBTeamStats,
    formatPlayerStats: formatMLBPlayerStats,
    seasonRange: { startMonth: 3, startDay: 20, endMonth: 11, endDay: 5 }, // Mar 20 – Nov 5
  },
  {
    sportKey: "icehockey_nhl",
    espnSport: "hockey/nhl",
    espnLeague: "nhl",
    playerTables: ["nhl_players"],
    formatTeamStats: formatNHLTeamStats,
    formatPlayerStats: formatNHLPlayerStats,
    seasonRange: { startMonth: 10, startDay: 1, endMonth: 6, endDay: 30 }, // Oct 1 – Jun 30
  },
  {
    sportKey: "americanfootball_nfl",
    espnSport: "football/nfl",
    espnLeague: "nfl",
    playerTables: ["nfl_qbs", "nfl_rbs", "nfl_receivers"],
    formatTeamStats: formatNFLTeamStats,
    formatPlayerStats: formatNFLPlayerStats,
    seasonRange: { startMonth: 9, startDay: 1, endMonth: 2, endDay: 15 }, // Sep 1 – Feb 15
  },
];

// ─── ESPN Stat Helpers ───────────────────────────────────────────────

function getStat(stats: any[], name: string): string {
  const s = stats?.find((s: any) => s.name === name || s.abbreviation === name);
  return s?.displayValue ?? s?.value?.toString() ?? "-";
}

function getStatValue(stats: any[], name: string): number {
  const s = stats?.find((s: any) => s.name === name || s.abbreviation === name);
  return s?.value ?? 0;
}

// ─── Team Stats Formatters ───────────────────────────────────────────

function formatNBATeamStats(entry: any): Record<string, string> {
  const stats = entry.stats || [];
  const wins = getStatValue(stats, "wins");
  const losses = getStatValue(stats, "losses");
  return {
    Record: `${wins}-${losses}`,
    Home: getStat(stats, "Home"),
    Road: getStat(stats, "Road"),
    L10: getStat(stats, "Last Ten Games") || getStat(stats, "L10"),
    Streak: getStat(stats, "streak"),
    "Pt Diff": getStat(stats, "differential") || getStat(stats, "pointDifferential"),
  };
}

function formatMLBTeamStats(entry: any): Record<string, string> {
  const stats = entry.stats || [];
  const wins = getStatValue(stats, "wins");
  const losses = getStatValue(stats, "losses");
  return {
    Record: `${wins}-${losses}`,
    Home: getStat(stats, "Home"),
    Road: getStat(stats, "Road"),
    L10: getStat(stats, "Last Ten Games") || getStat(stats, "L10"),
    Streak: getStat(stats, "streak"),
    RS: getStat(stats, "pointsFor"),
    RA: getStat(stats, "pointsAgainst"),
  };
}

function formatNHLTeamStats(entry: any): Record<string, string> {
  const stats = entry.stats || [];
  const wins = getStatValue(stats, "wins");
  const losses = getStatValue(stats, "losses");
  const otl = getStatValue(stats, "OTLosses") || getStatValue(stats, "otLosses");
  return {
    Record: otl ? `${wins}-${losses}-${otl}` : `${wins}-${losses}`,
    Home: getStat(stats, "Home"),
    Road: getStat(stats, "Road"),
    L10: getStat(stats, "Last Ten Games") || getStat(stats, "L10"),
    Points: getStat(stats, "points"),
    GF: getStat(stats, "pointsFor"),
    GA: getStat(stats, "pointsAgainst"),
  };
}

function formatNFLTeamStats(entry: any): Record<string, string> {
  const stats = entry.stats || [];
  const wins = getStatValue(stats, "wins");
  const losses = getStatValue(stats, "losses");
  const ties = getStatValue(stats, "ties");
  return {
    Record: ties ? `${wins}-${losses}-${ties}` : `${wins}-${losses}`,
    Home: getStat(stats, "Home"),
    Road: getStat(stats, "Road"),
    Div: getStat(stats, "vs. Div.") || getStat(stats, "divisionRecord"),
    PF: getStat(stats, "pointsFor"),
    PA: getStat(stats, "pointsAgainst"),
    Streak: getStat(stats, "streak"),
  };
}

// ─── Player Stats Formatters ─────────────────────────────────────────
// ESPN web API returns { categories: [{ name, names: string[], totals: string[] }] }

/** Build a flat name→value map from all ESPN stat categories (uses "averages" first, then all). */
function buildStatMap(data: any): Map<string, string> {
  const map = new Map<string, string>();
  const cats = data?.categories || [];
  // Prefer "averages" category for per-game stats; fall back to all categories
  const preferred = cats.find((c: any) => c.name === "averages") || cats[0];
  if (!preferred) return map;
  const names: string[] = preferred.names || [];
  const totals: string[] = preferred.totals || [];
  for (let i = 0; i < names.length; i++) {
    map.set(names[i], totals[i] ?? "-");
  }
  // Also merge other categories for stats not in averages
  for (const cat of cats) {
    if (cat === preferred) continue;
    const n: string[] = cat.names || [];
    const t: string[] = cat.totals || [];
    for (let i = 0; i < n.length; i++) {
      if (!map.has(n[i])) map.set(n[i], t[i] ?? "-");
    }
  }
  return map;
}

function formatNBAPlayerStats(data: any): Record<string, string> {
  const m = buildStatMap(data);
  if (m.size === 0) return {};
  return {
    PPG: m.get("avgPoints") ?? "-",
    RPG: m.get("avgRebounds") ?? "-",
    APG: m.get("avgAssists") ?? "-",
    "FG%": m.get("fieldGoalPct") ?? "-",
    "3P%": m.get("threePointFieldGoalPct") ?? "-",
    "FT%": m.get("freeThrowPct") ?? "-",
    SPG: m.get("avgSteals") ?? "-",
    BPG: m.get("avgBlocks") ?? "-",
    MPG: m.get("avgMinutes") ?? "-",
  };
}

function formatMLBPlayerStats(data: any): Record<string, string> {
  const m = buildStatMap(data);
  if (m.size === 0) return {};

  // Detect pitcher vs batter by presence of ERA
  if (m.has("ERA")) {
    return {
      ERA: m.get("ERA") ?? "-",
      "W-L": `${m.get("wins") ?? "0"}-${m.get("losses") ?? "0"}`,
      K: m.get("strikeouts") ?? m.get("SO") ?? "-",
      WHIP: m.get("WHIP") ?? "-",
      IP: m.get("innings") ?? m.get("inningsPitched") ?? "-",
    };
  } else {
    return {
      AVG: m.get("avg") ?? m.get("AVG") ?? "-",
      HR: m.get("homeRuns") ?? m.get("HR") ?? "-",
      RBI: m.get("RBIs") ?? m.get("RBI") ?? "-",
      OBP: m.get("OBP") ?? m.get("onBasePct") ?? "-",
      SLG: m.get("slugAvg") ?? m.get("SLG") ?? "-",
      R: m.get("runs") ?? "-",
      H: m.get("hits") ?? "-",
      SB: m.get("stolenBases") ?? m.get("SB") ?? "-",
    };
  }
}

function formatNHLPlayerStats(data: any): Record<string, string> {
  const m = buildStatMap(data);
  if (m.size === 0) return {};
  return {
    G: m.get("goals") ?? "-",
    A: m.get("assists") ?? "-",
    PTS: m.get("points") ?? "-",
    "+/-": m.get("plusMinus") ?? "-",
    PIM: m.get("penaltyMinutes") ?? "-",
    SOG: m.get("shots") ?? "-",
    TOI: m.get("avgTimeOnIce") ?? "-",
  };
}

function formatNFLPlayerStats(data: any, position?: string): Record<string, string> {
  const m = buildStatMap(data);
  if (m.size === 0) return {};

  if (position === "QB") {
    return {
      "Pass Yds": m.get("passingYards") ?? "-",
      "Pass TDs": m.get("passingTouchdowns") ?? "-",
      INTs: m.get("interceptions") ?? "-",
      Rating: m.get("QBRating") ?? "-",
      "Comp%": m.get("completionPct") ?? "-",
    };
  } else if (position === "RB") {
    return {
      "Rush Yds": m.get("rushingYards") ?? "-",
      "Rush TDs": m.get("rushingTouchdowns") ?? "-",
      YPC: m.get("yardsPerRushAttempt") ?? "-",
      Carries: m.get("rushingAttempts") ?? "-",
    };
  } else {
    // WR/TE
    return {
      "Rec Yds": m.get("receivingYards") ?? "-",
      "Rec TDs": m.get("receivingTouchdowns") ?? "-",
      Rec: m.get("receptions") ?? "-",
      "Yds/Rec": m.get("yardsPerReception") ?? "-",
    };
  }
}

// ─── Main Handler ────────────────────────────────────────────────────

Deno.serve(async (req) => {
  // JWT service_role verification
  const auth = req.headers.get("authorization") ?? "";
  const token = auth.replace(/^Bearer\s+/i, "");
  try {
    const [, payloadB64] = token.split(".");
    const payload = JSON.parse(
      atob(payloadB64.replace(/-/g, "+").replace(/_/g, "/"))
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

  try {
    const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);
    const summary: Record<string, any> = {};

    for (const config of SPORT_CONFIGS) {
      // Skip off-season sports — mirrors iOS isInSeason logic in LinesManager.swift
      if (!isInSeason(config)) {
        summary[config.sportKey] = { skipped: true, reason: "off-season" };
        continue;
      }

      const sportSummary: any = { teams: 0, players: 0, errors: 0 };

      // ─── Step 1: Fetch team standings from ESPN ───────────

      try {
        const standingsUrl = `https://site.api.espn.com/apis/v2/sports/${config.espnSport}/standings`;
        const standingsRes = await fetch(standingsUrl);

        if (standingsRes.ok) {
          const standingsData = await standingsRes.json();
          const teamRows: { team_name: string; sport_key: string; stats: Record<string, string>; updated_at: string }[] = [];

          // ESPN standings structure: children[] → standings → entries[]
          const children = standingsData.children || [];
          for (const group of children) {
            const entries = group.standings?.entries || [];
            for (const entry of entries) {
              const teamName = entry.team?.displayName;
              if (!teamName) continue;

              const stats = config.formatTeamStats(entry);
              teamRows.push({
                team_name: teamName,
                sport_key: config.sportKey,
                stats,
                updated_at: new Date().toISOString(),
              });
            }
          }

          if (teamRows.length > 0) {
            const { error } = await supabase
              .from("team_stats")
              .upsert(teamRows, { onConflict: "team_name,sport_key" });
            if (error) {
              console.error(`Team stats upsert error (${config.sportKey}): ${error.message}`);
              sportSummary.errors++;
            } else {
              sportSummary.teams = teamRows.length;
            }
          }
        }
      } catch (err) {
        console.error(`Standings fetch error (${config.sportKey}): ${err}`);
        sportSummary.errors++;
      }

      await sleep(100);

      // ─── Step 2: Discover active players from cached_player_props ───

      const { data: propRows } = await supabase
        .from("cached_player_props")
        .select("player_teams")
        .like("sport_key", `${config.sportKey}%`);

      // Collect unique player names and their teams
      const playerTeamMap = new Map<string, string>(); // playerName → teamName
      if (propRows) {
        for (const row of propRows) {
          const pt = row.player_teams as Record<string, string> | null;
          if (pt) {
            for (const [playerName, teamName] of Object.entries(pt)) {
              playerTeamMap.set(playerName, teamName);
            }
          }
        }
      }

      // Also discover players from cached_odds team names for team stat coverage
      const { data: oddsRows } = await supabase
        .from("cached_odds")
        .select("data")
        .eq("sport_key", config.sportKey);

      // Extract team names from odds data to ensure all active teams have stats
      const activeTeams = new Set<string>();
      if (oddsRows) {
        for (const row of oddsRows) {
          const events = row.data as any[];
          if (Array.isArray(events)) {
            for (const event of events) {
              if (event.home_team) activeTeams.add(event.home_team);
              if (event.away_team) activeTeams.add(event.away_team);
            }
          }
        }
      }

      // ─── Step 3: Look up ESPN IDs for active players ──────

      const espnIdMap = new Map<string, { espnId: number; position?: string }>();

      for (const table of config.playerTables) {
        const { data: players } = await supabase
          .from(table)
          .select("player_name, espn_id");

        if (players) {
          // Determine position from table name for NFL
          for (const p of players) {
            let position: string | undefined;
            if (table === "nfl_qbs") position = "QB";
            else if (table === "nfl_rbs") position = "RB";
            else if (table === "nfl_receivers") position = p.position || "WR";

            espnIdMap.set(p.player_name, {
              espnId: p.espn_id,
              position,
            });
          }
        }
      }

      // ─── Step 4: Fetch ESPN stats for each active player ──

      const playerStatsRows: {
        player_name: string;
        team_name: string;
        sport_key: string;
        stats: Record<string, string>;
        updated_at: string;
      }[] = [];

      for (const [playerName, teamName] of playerTeamMap.entries()) {
        const espnInfo = espnIdMap.get(playerName);
        if (!espnInfo) {
          // Try case-insensitive or partial match
          const match = [...espnIdMap.entries()].find(
            ([name]) => name.toLowerCase() === playerName.toLowerCase()
          );
          if (!match) {
            sportSummary.errors++;
            continue;
          }
          espnIdMap.set(playerName, match[1]);
        }

        const info = espnIdMap.get(playerName)!;
        try {
          const statsUrl = `https://site.web.api.espn.com/apis/common/v3/sports/${config.espnSport}/athletes/${info.espnId}/stats`;
          const res = await fetch(statsUrl);

          if (res.ok) {
            const data = await res.json();
            const stats = config.formatPlayerStats(data, info.position);

            if (Object.keys(stats).length > 0) {
              playerStatsRows.push({
                player_name: playerName,
                team_name: teamName,
                sport_key: config.sportKey,
                stats,
                updated_at: new Date().toISOString(),
              });
            }
          }
        } catch {
          sportSummary.errors++;
        }

        await sleep(150);
      }

      // Upsert player stats in batches
      if (playerStatsRows.length > 0) {
        for (let i = 0; i < playerStatsRows.length; i += 100) {
          const batch = playerStatsRows.slice(i, i + 100);
          const { error } = await supabase
            .from("player_stats")
            .upsert(batch, { onConflict: "player_name,team_name,sport_key" });
          if (error) {
            console.error(`Player stats upsert error (${config.sportKey}): ${error.message}`);
          }
        }
        sportSummary.players = playerStatsRows.length;
      }

      summary[config.sportKey] = sportSummary;
    }

    return new Response(JSON.stringify({ success: true, summary }), {
      status: 200,
      headers: { "Content-Type": "application/json" },
    });
  } catch (err) {
    return new Response(JSON.stringify({ error: String(err) }), {
      status: 500,
      headers: { "Content-Type": "application/json" },
    });
  }
});
