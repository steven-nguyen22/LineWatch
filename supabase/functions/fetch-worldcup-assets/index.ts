import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

// World Cup odds live under this sport_key (see fetch-worldcup-odds). We read
// the team names that actually appear from cached_odds and resolve a crest for
// each via ESPN, then upsert into the shared soccer_teams table — the same
// table iOS already loads in OddsDataService.fetchSoccerAssets(), so no app
// change is needed for the logos to appear. Logos only; player headshots are a
// separate follow-up.
const SPORT_KEY = "soccer_fifa_world_cup";

// ESPN's national-team list for the 2026 World Cup. Returns every nation with a
// numeric id and a ready-to-use logo href at teamlogos/countries/500/{abbr}.png
// (a DIFFERENT path than club logos — use the href verbatim, don't rebuild it).
const ESPN_TEAMS_URL =
  "https://site.api.espn.com/apis/site/v2/sports/soccer/fifa.world/teams";

// The Odds API spelling → ESPN displayName, for the nations whose names differ.
// Keys are normalized (see normalize()); add more here if `unresolved` is
// non-empty after a run.
const NAME_ALIASES: Record<string, string> = {
  "usa": "United States",
  "united states of america": "United States",
  "south korea": "Korea Republic",
  "north korea": "Korea DPR",
  "czech republic": "Czechia",
  "bosnia and herzegovina": "Bosnia and Herzegovina",
  "bosnia herzegovina": "Bosnia and Herzegovina",
  "ir iran": "Iran",
  "china pr": "China",
  "ivory coast": "Côte d'Ivoire",
  "cote divoire": "Côte d'Ivoire",
  "cape verde": "Cabo Verde",
  "curacao": "Curaçao",
  "turkey": "Türkiye",
  "republic of ireland": "Ireland",
  "dr congo": "Congo DR",
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
  logos?: { href?: string }[];
}

// deno-lint-ignore no-explicit-any
interface CachedOddsRow {
  data: any[];
}

Deno.serve(async (req) => {
  // Auth check — service-role JWT only (mirrors the other fetch-*-assets fns).
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

    // 1. Collect the distinct team names that actually appear in the WC odds.
    const { data: oddsRows, error: oddsErr } = await supabase
      .from("cached_odds")
      .select("data")
      .eq("sport_key", SPORT_KEY)
      .limit(1);

    if (oddsErr) {
      return new Response(JSON.stringify({ error: oddsErr.message }), {
        status: 500,
        headers: { "Content-Type": "application/json" },
      });
    }

    const events = (oddsRows?.[0] as CachedOddsRow | undefined)?.data ?? [];
    const teamNames = new Set<string>();
    for (const event of events) {
      if (event.home_team) teamNames.add(event.home_team);
      if (event.away_team) teamNames.add(event.away_team);
    }

    if (teamNames.size === 0) {
      return new Response(
        JSON.stringify({
          success: true,
          resolved: 0,
          upserted: 0,
          unresolved: [],
          note: "No World Cup teams in cached_odds yet — run fetch-worldcup-odds first.",
        }),
        { status: 200, headers: { "Content-Type": "application/json" } }
      );
    }

    // 2. Fetch ESPN's national-team list once and index it by normalized name.
    const espnRes = await fetch(ESPN_TEAMS_URL);
    if (!espnRes.ok) {
      const body = await espnRes.text();
      return new Response(
        JSON.stringify({ error: "ESPN teams fetch failed", status: espnRes.status, body }),
        { status: 502, headers: { "Content-Type": "application/json" } }
      );
    }
    const espnData = await espnRes.json();
    const espnTeams: ESPNTeam[] = (espnData?.sports?.[0]?.leagues?.[0]?.teams ?? [])
      // deno-lint-ignore no-explicit-any
      .map((t: any) => t.team as ESPNTeam)
      .filter((t: ESPNTeam | undefined): t is ESPNTeam => !!t && !!t.id);

    const espnByName = new Map<string, ESPNTeam>();
    for (const t of espnTeams) {
      if (t.displayName) espnByName.set(normalize(t.displayName), t);
      if (t.name) espnByName.set(normalize(t.name), t);
      if (t.abbreviation) espnByName.set(normalize(t.abbreviation), t);
    }

    // 3. Resolve each Odds API name → ESPN team (exact/alias/normalized).
    const rows: { team_name: string; espn_id: number; logo_url: string }[] = [];
    const unresolved: string[] = [];

    for (const oddsName of teamNames) {
      const key = normalize(oddsName);
      const aliasTarget = NAME_ALIASES[key];
      const team =
        espnByName.get(key) ??
        (aliasTarget ? espnByName.get(normalize(aliasTarget)) : undefined);

      const logo = team?.logos?.[0]?.href;
      if (team && logo) {
        rows.push({
          team_name: oddsName,
          espn_id: parseInt(team.id, 10),
          logo_url: logo,
        });
      } else {
        unresolved.push(oddsName);
      }
    }

    // 4. Upsert resolved crests into the shared soccer_teams table.
    let upserted = 0;
    if (rows.length > 0) {
      const { error: upsertErr } = await supabase
        .from("soccer_teams")
        .upsert(rows, { onConflict: "team_name" });
      if (upsertErr) {
        return new Response(
          JSON.stringify({ error: "Failed to upsert teams", detail: upsertErr.message }),
          { status: 500, headers: { "Content-Type": "application/json" } }
        );
      }
      upserted = rows.length;
    }

    return new Response(
      JSON.stringify({
        success: true,
        teams_in_odds: teamNames.size,
        resolved: rows.length,
        upserted,
        unresolved,
      }),
      { status: 200, headers: { "Content-Type": "application/json" } }
    );
  } catch (err) {
    return new Response(JSON.stringify({ error: String(err) }), {
      status: 500,
      headers: { "Content-Type": "application/json" },
    });
  }
});
