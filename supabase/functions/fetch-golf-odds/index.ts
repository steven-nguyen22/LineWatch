import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const ODDS_API_KEY = Deno.env.get("ODDS_API_KEY")!;
const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

// Old hardcoded keys — cleaned up on first deploy
const LEGACY_KEYS = [
  "golf_masters_tournament_winner",
  "golf_pga_championship_winner",
  "golf_the_open_championship_winner",
  "golf_us_open_winner",
];

function sleep(ms: number): Promise<void> {
  return new Promise((r) => setTimeout(r, ms));
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
    const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);

    // Step 1: Discover active golf tournaments from the Odds API (1 credit)
    const sportsRes = await fetch(
      `https://api.the-odds-api.com/v4/sports?apiKey=${ODDS_API_KEY}`
    );

    if (!sportsRes.ok) {
      const body = await sportsRes.text();
      return new Response(
        JSON.stringify({ error: "Odds API error fetching sports", status: sportsRes.status, body }),
        { status: 502, headers: { "Content-Type": "application/json" } }
      );
    }

    // deno-lint-ignore no-explicit-any
    const allSports: any[] = await sportsRes.json();
    const activeGolfKeys: string[] = allSports
      .filter((s) => s.group === "Golf" && s.active === true)
      .map((s) => s.key);

    // Clean up legacy individual tournament rows (one-time migration, harmless to keep)
    await supabase.from("cached_odds").delete().in("sport_key", LEGACY_KEYS);

    // No active tournaments — clear stale combined row and return
    if (activeGolfKeys.length === 0) {
      await supabase.from("cached_odds").delete().eq("sport_key", "golf");
      return new Response(
        JSON.stringify({ success: true, active_tournaments: 0, events: 0 }),
        { status: 200, headers: { "Content-Type": "application/json" } }
      );
    }

    // Step 2: Fetch odds for each active tournament and combine into one array
    // deno-lint-ignore no-explicit-any
    const allEvents: any[] = [];

    for (let i = 0; i < activeGolfKeys.length; i++) {
      const key = activeGolfKeys[i];
      const url = `https://api.the-odds-api.com/v4/sports/${key}/odds/?apiKey=${ODDS_API_KEY}&regions=us&markets=outrights&oddsFormat=american`;
      const res = await fetch(url);

      if (!res.ok) {
        // Skip failed tournaments rather than aborting the whole run
        console.error(`Failed to fetch ${key}: ${res.status}`);
        continue;
      }

      const events = await res.json();
      if (Array.isArray(events)) {
        allEvents.push(...events);
      }

      if (i < activeGolfKeys.length - 1) await sleep(200);
    }

    // Step 3: Upsert all active tournament events as a single "golf" row
    const { error } = await supabase.from("cached_odds").upsert({
      sport_key: "golf",
      data: allEvents,
      updated_at: new Date().toISOString(),
    });

    if (error) {
      return new Response(JSON.stringify({ error: error.message }), {
        status: 500,
        headers: { "Content-Type": "application/json" },
      });
    }

    return new Response(
      JSON.stringify({
        success: true,
        active_tournaments: activeGolfKeys.length,
        tournament_keys: activeGolfKeys,
        events: allEvents.length,
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
