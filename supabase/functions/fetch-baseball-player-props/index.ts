import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const ODDS_API_KEY = Deno.env.get("ODDS_API_KEY")!;
const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

const SPORT_KEY = "baseball_mlb";
const PROP_MARKETS = "batter_hits,pitcher_strikeouts,batter_home_runs";

// ESPN team name → ESPN numeric team ID mapping
// Team names match The Odds API format
const MLB_TEAM_IDS: Record<string, number> = {
  "Arizona Diamondbacks": 29,
  "Atlanta Braves": 15,
  "Baltimore Orioles": 1,
  "Boston Red Sox": 2,
  "Chicago Cubs": 16,
  "Chicago White Sox": 4,
  "Cincinnati Reds": 17,
  "Cleveland Guardians": 5,
  "Colorado Rockies": 27,
  "Detroit Tigers": 6,
  "Houston Astros": 18,
  "Kansas City Royals": 7,
  "Los Angeles Angels": 3,
  "Los Angeles Dodgers": 19,
  "Miami Marlins": 28,
  "Milwaukee Brewers": 8,
  "Minnesota Twins": 9,
  "New York Mets": 21,
  "New York Yankees": 10,
  "Oakland Athletics": 11,
  "Philadelphia Phillies": 22,
  "Pittsburgh Pirates": 23,
  "San Diego Padres": 25,
  "San Francisco Giants": 26,
  "Seattle Mariners": 12,
  "St. Louis Cardinals": 24,
  "Tampa Bay Rays": 30,
  "Texas Rangers": 13,
  "Toronto Blue Jays": 14,
  "Washington Nationals": 20,
};

// Cache rosters across events to avoid redundant ESPN calls
const rosterCache = new Map<number, string[]>();

/** Fetch a team's roster from ESPN's free public API */
async function fetchTeamRoster(teamId: number): Promise<string[]> {
  if (rosterCache.has(teamId)) {
    return rosterCache.get(teamId)!;
  }

  try {
    const url = `https://site.api.espn.com/apis/site/v2/sports/baseball/mlb/teams/${teamId}/roster`;
    const res = await fetch(url);
    if (!res.ok) {
      rosterCache.set(teamId, []);
      return [];
    }

    const data = await res.json();
    const names: string[] = [];

    // ESPN MLB roster may have athletes as flat array or nested in position groups
    if (Array.isArray(data.athletes)) {
      for (const item of data.athletes) {
        // Check if it's a position group with nested items
        if (Array.isArray(item.items)) {
          for (const athlete of item.items) {
            if (athlete.displayName) {
              names.push(athlete.displayName);
            }
          }
        } else if (item.displayName) {
          // Flat array of athletes
          names.push(item.displayName);
        }
      }
    }

    rosterCache.set(teamId, names);
    return names;
  } catch {
    rosterCache.set(teamId, []);
    return [];
  }
}

/** Build a player name → team name mapping for an event */
async function buildPlayerTeamMap(
  homeTeam: string,
  awayTeam: string,
  // deno-lint-ignore no-explicit-any
  propsData: any
): Promise<Record<string, string>> {
  const homeId = MLB_TEAM_IDS[homeTeam];
  const awayId = MLB_TEAM_IDS[awayTeam];

  if (!homeId && !awayId) {
    return {};
  }

  const [homeRoster, awayRoster] = await Promise.all([
    homeId ? fetchTeamRoster(homeId) : Promise.resolve([]),
    awayId ? fetchTeamRoster(awayId) : Promise.resolve([]),
  ]);

  const homeSet = new Set(homeRoster.map((n) => n.toLowerCase()));
  const awaySet = new Set(awayRoster.map((n) => n.toLowerCase()));

  const playerNames = new Set<string>();
  for (const bookmaker of propsData.bookmakers || []) {
    for (const market of bookmaker.markets || []) {
      for (const outcome of market.outcomes || []) {
        if (outcome.description) {
          playerNames.add(outcome.description);
        }
      }
    }
  }

  const mapping: Record<string, string> = {};
  for (const name of playerNames) {
    const lower = name.toLowerCase();
    if (homeSet.has(lower)) {
      mapping[name] = homeTeam;
    } else if (awaySet.has(lower)) {
      mapping[name] = awayTeam;
    }
  }

  return mapping;
}

Deno.serve(async (req) => {
  // Supabase validates the JWT signature (verify_jwt = true in config.toml).
  // We additionally check the role claim so anon-key callers are blocked.
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

  try {
    // Step 1: Get current MLB event IDs
    const eventsUrl = `https://api.the-odds-api.com/v4/sports/${SPORT_KEY}/events?apiKey=${ODDS_API_KEY}`;
    const eventsRes = await fetch(eventsUrl);

    if (!eventsRes.ok) {
      const body = await eventsRes.text();
      return new Response(
        JSON.stringify({ error: "Events API error", status: eventsRes.status, body }),
        { status: 502, headers: { "Content-Type": "application/json" } }
      );
    }

    const events: { id: string }[] = await eventsRes.json();
    const eventIds = events.map((e) => e.id);

    const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);
    let successCount = 0;
    let failCount = 0;

    // Step 2: Fetch player props for each event
    for (const eventId of eventIds) {
      try {
        const propsUrl = `https://api.the-odds-api.com/v4/sports/${SPORT_KEY}/events/${eventId}/odds/?apiKey=${ODDS_API_KEY}&regions=us&markets=${PROP_MARKETS}&oddsFormat=american`;
        const propsRes = await fetch(propsUrl);

        if (!propsRes.ok) {
          failCount++;
          continue;
        }

        const propsData = await propsRes.json();

        // Build player → team mapping using ESPN rosters
        const playerTeams = await buildPlayerTeamMap(
          propsData.home_team || "",
          propsData.away_team || "",
          propsData
        );

        // Step 3: Upsert into cached_player_props
        const { error } = await supabase.from("cached_player_props").upsert({
          event_id: eventId,
          sport_key: SPORT_KEY,
          data: propsData,
          player_teams: playerTeams,
          updated_at: new Date().toISOString(),
        });

        if (error) {
          failCount++;
        } else {
          successCount++;
        }

        // Rate limit courtesy — 200ms between requests
        await new Promise((resolve) => setTimeout(resolve, 200));
      } catch {
        failCount++;
      }
    }

    // Step 4: Delete stale rows (events no longer active)
    if (eventIds.length > 0) {
      await supabase
        .from("cached_player_props")
        .delete()
        .eq("sport_key", SPORT_KEY)
        .not("event_id", "in", `(${eventIds.join(",")})`);
    }

    return new Response(
      JSON.stringify({
        success: true,
        total_events: eventIds.length,
        cached: successCount,
        failed: failCount,
        roster_cache_size: rosterCache.size,
      }),
      { status: 200, headers: { "Content-Type": "application/json" } }
    );
  } catch (err) {
    return new Response(
      JSON.stringify({ error: String(err) }),
      { status: 500, headers: { "Content-Type": "application/json" } }
    );
  }
});
