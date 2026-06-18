import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const ODDS_API_KEY = Deno.env.get("ODDS_API_KEY")!;
const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

// FIFA World Cup props. Mirrors fetch-soccer-player-props (UEFA Champions
// League), but resolves national-team rosters dynamically from ESPN's
// fifa.world endpoint instead of a hardcoded club-ID map — the same approach
// proven in fetch-worldcup-assets. Writes to the shared cached_player_props
// table with sport_key = soccer_fifa_world_cup, which the iOS app already reads
// by event_id (no app change needed).
const SPORT_KEY = "soccer_fifa_world_cup";
const PROP_MARKETS =
  "player_goal_scorer_anytime,player_shots_on_target,player_shots_on_target_alternate,player_assists";

// ESPN's national-team list for the 2026 World Cup — each nation with a numeric
// id and rosters available at fifa.world/teams/{id}/roster.
const ESPN_TEAMS_URL =
  "https://site.api.espn.com/apis/site/v2/sports/soccer/fifa.world/teams";

// The Odds API spelling → ESPN displayName, for nations whose names differ.
// Keys MUST be in normalized form (see normalize()); values are normalized at
// lookup time so they can stay human-readable. Add more if a run leaves teams
// unresolved. (Kept in sync with fetch-worldcup-assets.)
const NAME_ALIASES: Record<string, string> = {
  "usa": "United States",
  "unitedstatesofamerica": "United States",
  "southkorea": "Korea Republic",
  "northkorea": "Korea DPR",
  "czechrepublic": "Czechia",
  "iriran": "Iran",
  "chinapr": "China",
  "ivorycoast": "Côte d'Ivoire",
  "capeverde": "Cabo Verde",
  "turkey": "Türkiye",
  "republicofireland": "Ireland",
  "drcongo": "Congo DR",
};

// Lowercase, strip diacritics and non-alphanumerics for tolerant matching.
function normalize(s: string): string {
  return s
    .normalize("NFD")
    .replace(/[̀-ͯ]/g, "")
    .toLowerCase()
    .replace(/[^a-z0-9]/g, "");
}

interface ESPNTeam {
  id: string;
  displayName: string;
  name?: string;
  abbreviation?: string;
}

// Maps a normalized national-team name → ESPN numeric id. Built once per run.
const espnIdByName = new Map<string, number>();

/** Fetch ESPN's national-team list once and index it by normalized name. */
async function loadNationalTeamIds(): Promise<void> {
  const res = await fetch(ESPN_TEAMS_URL);
  if (!res.ok) return;
  const data = await res.json();
  const teams: ESPNTeam[] = (data?.sports?.[0]?.leagues?.[0]?.teams ?? [])
    // deno-lint-ignore no-explicit-any
    .map((t: any) => t.team as ESPNTeam)
    .filter((t: ESPNTeam | undefined): t is ESPNTeam => !!t && !!t.id);

  for (const t of teams) {
    const id = parseInt(t.id, 10);
    if (Number.isNaN(id)) continue;
    if (t.displayName) espnIdByName.set(normalize(t.displayName), id);
    if (t.name) espnIdByName.set(normalize(t.name), id);
    if (t.abbreviation) espnIdByName.set(normalize(t.abbreviation), id);
  }
}

/** Resolve a national-team name (Odds API spelling) → ESPN id. */
function resolveTeamId(teamName: string): number | undefined {
  const key = normalize(teamName);
  const direct = espnIdByName.get(key);
  if (direct !== undefined) return direct;
  const alias = NAME_ALIASES[key];
  if (alias) return espnIdByName.get(normalize(alias));
  return undefined;
}

// Cache rosters across events to avoid redundant ESPN calls.
const rosterCache = new Map<number, string[]>();

/** Fetch a national team's roster from ESPN's free public API. */
async function fetchTeamRoster(teamId: number): Promise<string[]> {
  if (rosterCache.has(teamId)) {
    return rosterCache.get(teamId)!;
  }

  try {
    const url = `https://site.api.espn.com/apis/site/v2/sports/soccer/fifa.world/teams/${teamId}/roster`;
    const res = await fetch(url);
    if (!res.ok) {
      rosterCache.set(teamId, []);
      return [];
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

  // ESPN soccer roster may use nested position groups or a flat array.
  if (Array.isArray(data.athletes)) {
    for (const item of data.athletes) {
      if (Array.isArray(item.items)) {
        for (const athlete of item.items) {
          if (athlete.displayName) names.push(athlete.displayName);
        }
      } else if (item.displayName) {
        names.push(item.displayName);
      }
    }
  }

  rosterCache.set(teamId, names);
  return names;
}

/** Build a player name → team name mapping for an event (best-effort). */
async function buildPlayerTeamMap(
  homeTeam: string,
  awayTeam: string,
  // deno-lint-ignore no-explicit-any
  propsData: any
): Promise<Record<string, string>> {
  const homeId = resolveTeamId(homeTeam);
  const awayId = resolveTeamId(awayTeam);

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
        if (outcome.description) playerNames.add(outcome.description);
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
    // Step 0: Index ESPN national-team ids once (best-effort; props still work
    // without it — player_teams just ends up empty).
    await loadNationalTeamIds();

    // Step 1: Get current World Cup event IDs.
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

    // Step 2: Fetch player props for each event.
    for (const eventId of eventIds) {
      try {
        const propsUrl = `https://api.the-odds-api.com/v4/sports/${SPORT_KEY}/events/${eventId}/odds/?apiKey=${ODDS_API_KEY}&regions=us&markets=${PROP_MARKETS}&oddsFormat=american`;
        const propsRes = await fetch(propsUrl);

        if (!propsRes.ok) {
          failCount++;
          continue;
        }

        const propsData = await propsRes.json();

        // Build player → team mapping using ESPN national-team rosters.
        const playerTeams = await buildPlayerTeamMap(
          propsData.home_team || "",
          propsData.away_team || "",
          propsData
        );

        // Step 3: Upsert into cached_player_props.
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

        // Rate limit courtesy - 200ms between requests.
        await new Promise((resolve) => setTimeout(resolve, 200));
      } catch {
        failCount++;
      }
    }

    // Step 4: Delete stale rows (events no longer active).
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
        teams_indexed: espnIdByName.size,
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
