import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const ODDS_API_KEY = Deno.env.get("ODDS_API_KEY")!;
const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

const SPORT_KEYS = [
  "golf_masters_tournament_winner",
  "golf_pga_championship_winner",
  "golf_the_open_championship_winner",
  "golf_us_open_winner",
] as const;

Deno.serve(async (_req) => {
  try {
    const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);
    const tournaments: Record<string, number> = {};

    for (let i = 0; i < SPORT_KEYS.length; i++) {
      const key = SPORT_KEYS[i];
      const url = `https://api.the-odds-api.com/v4/sports/${key}/odds/?apiKey=${ODDS_API_KEY}&regions=us&markets=outrights&oddsFormat=american`;
      const res = await fetch(url);

      if (!res.ok) {
        const body = await res.text();
        return new Response(
          JSON.stringify({ error: "Odds API error", sport_key: key, status: res.status, body }),
          { status: 502, headers: { "Content-Type": "application/json" } }
        );
      }

      const data = await res.json();

      const { error } = await supabase.from("cached_odds").upsert({
        sport_key: key,
        data: data,
        updated_at: new Date().toISOString(),
      });

      if (error) {
        return new Response(JSON.stringify({ error: error.message, sport_key: key }), {
          status: 500,
          headers: { "Content-Type": "application/json" },
        });
      }

      tournaments[key] = Array.isArray(data) ? data.length : 0;

      if (i < SPORT_KEYS.length - 1) {
        await new Promise((r) => setTimeout(r, 200));
      }
    }

    return new Response(
      JSON.stringify({ success: true, tournaments }),
      { status: 200, headers: { "Content-Type": "application/json" } }
    );
  } catch (err) {
    return new Response(
      JSON.stringify({ error: String(err) }),
      { status: 500, headers: { "Content-Type": "application/json" } }
    );
  }
});
