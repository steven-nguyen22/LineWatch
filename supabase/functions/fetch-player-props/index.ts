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

/**
 * Normalize a player name for cross-source matching.
 * Handles variance between ESPN ("R.J. Barrett", "Kelly Oubre Jr.") and
 * The Odds API ("RJ Barrett", "Kelly Oubre Jr"). Strips:
 *  - all periods and commas
 *  - trailing generational suffixes (jr/sr/ii/iii/iv)
 *  - case and extra whitespace
 */
function normalizePlayerName(name: string): string {
  return name
    .toLowerCase()
    .replace(/[.,]/g, "")                    // remove periods, commas
    .replace(/\s+(jr|sr|ii|iii|iv)\b/g, "")  // strip generational suffix
    .replace(/\s+/g, " ")                    // collapse whitespace
    .trim();
}

/**
 * Build a player → team mapping and a raw-name → canonical-name map for an event.
 *
 * `teams` is keyed by the canonical ESPN displayName (e.g. "R.J. Barrett"),
 * matching what the iOS client already keys headshots by.
 * `canonical` lets the caller rewrite Odds-API outcome descriptions to the
 * ESPN spelling before caching, so the client renders correct headshots too.
 */
async function buildPlayerTeamMap(
  homeTeam: string,
  awayTeam: string,
  // deno-lint-ignore no-explicit-any
  propsData: any
): Promise<{
  teams: Record<string, string>;
  canonical: Record<string, string>;
}> {
  const homeId = NBA_TEAM_IDS[homeTeam];
  const awayId = NBA_TEAM_IDS[awayTeam];

  if (!homeId && !awayId) {
    return { teams: {}, canonical: {} };
  }

  // Fetch both rosters in parallel
  const [homeRoster, awayRoster] = await Promise.all([
    homeId ? fetchTeamRoster(homeId) : Promise.resolve([]),
    awayId ? fetchTeamRoster(awayId) : Promise.resolve([]),
  ]);

  // Normalized → ESPN displayName per team
  const homeMap = new Map<string, string>();
  for (const n of homeRoster) homeMap.set(normalizePlayerName(n), n);
  const awayMap = new Map<string, string>();
  for (const n of awayRoster) awayMap.set(normalizePlayerName(n), n);

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

  const teams: Record<string, string> = {};
  const canonical: Record<string, string> = {};
  for (const raw of playerNames) {
    const key = normalizePlayerName(raw);
    const espnName = homeMap.get(key) ?? awayMap.get(key);
    if (!espnName) continue; // still unmapped — handled as "unknown" on client
    canonical[raw] = espnName;
    teams[espnName] = homeMap.has(key) ? homeTeam : awayTeam;
  }

  return { teams, canonical };
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
        const { teams: playerTeams, canonical } = await buildPlayerTeamMap(
          propsData.home_team || "",
          propsData.away_team || "",
          propsData
        );

        // Rewrite Odds-API names to ESPN canonical spellings so client-side
        // headshot lookups (keyed by ESPN displayName) succeed.
        for (const bookmaker of propsData.bookmakers || []) {
          for (const market of bookmaker.markets || []) {
            for (const outcome of market.outcomes || []) {
              if (outcome.description && canonical[outcome.description]) {
                outcome.description = canonical[outcome.description];
              }
            }
          }
        }

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
