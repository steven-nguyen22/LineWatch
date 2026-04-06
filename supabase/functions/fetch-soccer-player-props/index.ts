import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const ODDS_API_KEY = Deno.env.get("ODDS_API_KEY")!;
const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

const SPORT_KEY = "soccer_uefa_champs_league";
const PROP_MARKETS =
  "player_goal_scorer_anytime,player_shots_on_target,player_assists";

// ESPN team name -> ESPN numeric team ID mapping
// Team names match The Odds API format for UEFA Champions League
// NOTE: UCL participants change each season — update this mapping yearly
const SOCCER_TEAM_IDS: Record<string, number> = {
  // England
  "Arsenal": 359,
  "Aston Villa": 362,
  "Liverpool": 364,
  "Manchester City": 382,
  "Manchester United": 360,
  "Chelsea": 363,
  "Tottenham Hotspur": 367,
  // Spain
  "Barcelona": 83,
  "Real Madrid": 86,
  "Atletico Madrid": 1068,
  "Atlético Madrid": 1068,
  "Girona": 9812,
  // Germany
  "Bayern Munich": 132,
  "Borussia Dortmund": 124,
  "RB Leipzig": 11420,
  "Bayer Leverkusen": 131,
  "VfB Stuttgart": 134,
  // Italy
  "AC Milan": 103,
  "Inter Milan": 110,
  "Internazionale": 110,
  "Juventus": 111,
  "Atalanta": 102,
  "Bologna": 107,
  // France
  "Paris Saint-Germain": 160,
  "Paris Saint Germain": 160,
  "PSG": 160,
  "Monaco": 174,
  "Brest": 1417,
  "Lille": 166,
  // Portugal
  "Benfica": 1864,
  "Sporting CP": 2010,
  "Sporting Lisbon": 2010,
  "Porto": 1903,
  // Netherlands
  "PSV Eindhoven": 148,
  "PSV": 148,
  "Feyenoord": 143,
  // Others
  "Celtic": 285,
  "Club Brugge": 2356,
  "Red Star Belgrade": 2047,
  "Crvena Zvezda": 2047,
  "Young Boys": 3054,
  "Salzburg": 3003,
  "Red Bull Salzburg": 3003,
  "Shakhtar Donetsk": 3040,
  "Dinamo Zagreb": 2585,
  "GNK Dinamo Zagreb": 2585,
  "Slovan Bratislava": 3061,
  "Sturm Graz": 2999,
  "Sparta Prague": 2962,
  "Sparta Praha": 2962,
};

// Cache rosters across events to avoid redundant ESPN calls
const rosterCache = new Map<number, string[]>();

/** Fetch a team's roster from ESPN's free public API */
async function fetchTeamRoster(teamId: number): Promise<string[]> {
  if (rosterCache.has(teamId)) {
    return rosterCache.get(teamId)!;
  }

  try {
    // ESPN soccer rosters use the generic soccer endpoint
    const url = `https://site.api.espn.com/apis/site/v2/sports/soccer/uefa.champions/teams/${teamId}/roster`;
    const res = await fetch(url);
    if (!res.ok) {
      // Try the generic football endpoint as fallback
      const fallbackUrl = `https://site.api.espn.com/apis/site/v2/sports/soccer/eng.1/teams/${teamId}/roster`;
      const fallbackRes = await fetch(fallbackUrl);
      if (!fallbackRes.ok) {
        rosterCache.set(teamId, []);
        return [];
      }
      const data = await fallbackRes.json();
      return parseRoster(teamId, data);
    }

    const data = await res.json();
    return parseRoster(teamId, data);
  } catch {
    rosterCache.set(teamId, []);
    return [];
  }
}

// deno-lint-ignore no-explicit-any
function parseRoster(teamId: number, data: any): string[] {
  const names: string[] = [];

  // ESPN soccer roster may use nested position groups or a flat array
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
        // Flat array of athletes (fallback)
        names.push(item.displayName);
      }
    }
  }

  rosterCache.set(teamId, names);
  return names;
}

/** Build a player name -> team name mapping for an event */
async function buildPlayerTeamMap(
  homeTeam: string,
  awayTeam: string,
  // deno-lint-ignore no-explicit-any
  propsData: any
): Promise<Record<string, string>> {
  const homeId = SOCCER_TEAM_IDS[homeTeam];
  const awayId = SOCCER_TEAM_IDS[awayTeam];

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
    // Step 1: Get current UEFA Champions League event IDs
    const eventsUrl = `https://api.the-odds-api.com/v4/sports/${SPORT_KEY}/events?apiKey=${ODDS_API_KEY}`;
    const eventsRes = await fetch(eventsUrl);

    if (!eventsRes.ok) {
      const body = await eventsRes.text();
      return new Response(
        JSON.stringify({
          error: "Events API error",
          status: eventsRes.status,
          body,
        }),
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

        // Build player -> team mapping using ESPN rosters
        const playerTeams = await buildPlayerTeamMap(
          propsData.home_team || "",
          propsData.away_team || "",
          propsData
        );

        // Step 3: Upsert into cached_player_props
        const { error } = await supabase
          .from("cached_player_props")
          .upsert({
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

        // Rate limit courtesy - 200ms between requests
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
