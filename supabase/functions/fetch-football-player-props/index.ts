import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const ODDS_API_KEY = Deno.env.get("ODDS_API_KEY")!;
const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

const SPORT_KEY = "americanfootball_nfl";
const PROP_MARKETS = "player_pass_yds,player_rush_yds,player_reception_yds";

// ESPN team name → ESPN numeric team ID mapping
// Team names match The Odds API format
const NFL_TEAM_IDS: Record<string, number> = {
  "Arizona Cardinals": 22,
  "Atlanta Falcons": 1,
  "Baltimore Ravens": 33,
  "Buffalo Bills": 2,
  "Carolina Panthers": 29,
  "Chicago Bears": 3,
  "Cincinnati Bengals": 4,
  "Cleveland Browns": 5,
  "Dallas Cowboys": 6,
  "Denver Broncos": 7,
  "Detroit Lions": 8,
  "Green Bay Packers": 9,
  "Houston Texans": 34,
  "Indianapolis Colts": 11,
  "Jacksonville Jaguars": 30,
  "Kansas City Chiefs": 12,
  "Las Vegas Raiders": 13,
  "Los Angeles Chargers": 24,
  "Los Angeles Rams": 14,
  "Miami Dolphins": 15,
  "Minnesota Vikings": 16,
  "New England Patriots": 17,
  "New Orleans Saints": 18,
  "New York Giants": 19,
  "New York Jets": 20,
  "Philadelphia Eagles": 21,
  "Pittsburgh Steelers": 23,
  "San Francisco 49ers": 25,
  "Seattle Seahawks": 26,
  "Tampa Bay Buccaneers": 27,
  "Tennessee Titans": 10,
  "Washington Commanders": 28,
};

// Cache rosters across events to avoid redundant ESPN calls
const rosterCache = new Map<number, string[]>();

/** Fetch a team's roster from ESPN's free public API */
async function fetchTeamRoster(teamId: number): Promise<string[]> {
  if (rosterCache.has(teamId)) {
    return rosterCache.get(teamId)!;
  }

  try {
    const url = `https://site.api.espn.com/apis/site/v2/sports/football/nfl/teams/${teamId}/roster`;
    const res = await fetch(url);
    if (!res.ok) {
      rosterCache.set(teamId, []);
      return [];
    }

    const data = await res.json();
    const names: string[] = [];

    // ESPN NFL roster uses nested position groups (offense/defense/specialTeams)
    if (Array.isArray(data.athletes)) {
      for (const item of data.athletes) {
        if (Array.isArray(item.items)) {
          for (const athlete of item.items) {
            if (athlete.displayName) {
              names.push(athlete.displayName);
            }
          }
        } else if (item.displayName) {
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
  const homeId = NFL_TEAM_IDS[homeTeam];
  const awayId = NFL_TEAM_IDS[awayTeam];

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
  const auth = req.headers.get("authorization") ?? "";
  const token = auth.replace(/^Bearer\s+/i, "");
  if (token !== SUPABASE_SERVICE_ROLE_KEY) {
    return new Response(JSON.stringify({ error: "unauthorized" }), {
      status: 401,
      headers: { "Content-Type": "application/json" },
    });
  }

  try {
    // Step 1: Get current NFL event IDs
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
