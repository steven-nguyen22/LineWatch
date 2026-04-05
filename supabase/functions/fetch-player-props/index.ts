import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const ODDS_API_KEY = Deno.env.get("ODDS_API_KEY")!;
const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

const SPORT_KEY = "basketball_nba";
const PROP_MARKETS = "player_points,player_rebounds,player_assists";

// ESPN team name → ESPN numeric team ID mapping
// Team names match The Odds API format (e.g., "Boston Celtics")
const NBA_TEAM_IDS: Record<string, number> = {
  "Atlanta Hawks": 1,
  "Boston Celtics": 2,
  "Brooklyn Nets": 17,
  "Charlotte Hornets": 30,
  "Chicago Bulls": 4,
  "Cleveland Cavaliers": 5,
  "Dallas Mavericks": 6,
  "Denver Nuggets": 7,
  "Detroit Pistons": 8,
  "Golden State Warriors": 9,
  "Houston Rockets": 10,
  "Indiana Pacers": 11,
  "Los Angeles Clippers": 12,
  "LA Clippers": 12,
  "Los Angeles Lakers": 13,
  "LA Lakers": 13,
  "Memphis Grizzlies": 29,
  "Miami Heat": 14,
  "Milwaukee Bucks": 15,
  "Minnesota Timberwolves": 16,
  "New Orleans Pelicans": 3,
  "New York Knicks": 18,
  "Oklahoma City Thunder": 25,
  "Orlando Magic": 19,
  "Philadelphia 76ers": 20,
  "Phoenix Suns": 21,
  "Portland Trail Blazers": 22,
  "Sacramento Kings": 23,
  "San Antonio Spurs": 24,
  "Toronto Raptors": 28,
  "Utah Jazz": 26,
  "Washington Wizards": 27,
};

// Cache rosters across events to avoid redundant ESPN calls
const rosterCache = new Map<number, string[]>();

/** Fetch a team's roster from ESPN's free public API */
async function fetchTeamRoster(teamId: number): Promise<string[]> {
  // Check cache first
  if (rosterCache.has(teamId)) {
    return rosterCache.get(teamId)!;
  }

  try {
    const url = `https://site.api.espn.com/apis/site/v2/sports/basketball/nba/teams/${teamId}/roster`;
    const res = await fetch(url);
    if (!res.ok) {
      rosterCache.set(teamId, []);
      return [];
    }

    const data = await res.json();
    const names: string[] = [];

    // ESPN roster response has "athletes" array of athlete objects
    if (Array.isArray(data.athletes)) {
      for (const athlete of data.athletes) {
        if (athlete.displayName) {
          names.push(athlete.displayName);
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
  const homeId = NBA_TEAM_IDS[homeTeam];
  const awayId = NBA_TEAM_IDS[awayTeam];

  if (!homeId && !awayId) {
    return {};
  }

  // Fetch both rosters in parallel
  const [homeRoster, awayRoster] = await Promise.all([
    homeId ? fetchTeamRoster(homeId) : Promise.resolve([]),
    awayId ? fetchTeamRoster(awayId) : Promise.resolve([]),
  ]);

  // Build lowercase lookup sets for case-insensitive matching
  const homeSet = new Set(homeRoster.map((n) => n.toLowerCase()));
  const awaySet = new Set(awayRoster.map((n) => n.toLowerCase()));

  // Extract unique player names from props data
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

  // Map each player to their team
  const mapping: Record<string, string> = {};
  for (const name of playerNames) {
    const lower = name.toLowerCase();
    if (homeSet.has(lower)) {
      mapping[name] = homeTeam;
    } else if (awaySet.has(lower)) {
      mapping[name] = awayTeam;
    }
    // Players not found in either roster are omitted (handled as "unknown" on client)
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
    // Step 1: Get current NBA event IDs
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
