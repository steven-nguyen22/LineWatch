import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const ODDS_API_KEY = Deno.env.get("ODDS_API_KEY")!;
const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

const SPORT_KEYS = ["mma_mixed_martial_arts", "boxing_boxing"] as const;

Deno.serve(async (_req) => {
  try {
    const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);
    const counts: Record<string, number> = {};

    for (let i = 0; i < SPORT_KEYS.length; i++) {
      const key = SPORT_KEYS[i];
      const url = `https://api.the-odds-api.com/v4/sports/${key}/odds/?apiKey=${ODDS_API_KEY}&regions=us&markets=h2h&oddsFormat=american`;
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

      counts[key] = Array.isArray(data) ? data.length : 0;

      // Rate limit between Odds API calls
      if (i < SPORT_KEYS.length - 1) {
        await new Promise((r) => setTimeout(r, 200));
      }
    }

    return new Response(
      JSON.stringify({
        success: true,
        mma: counts["mma_mixed_martial_arts"] ?? 0,
        boxing: counts["boxing_boxing"] ?? 0,
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
