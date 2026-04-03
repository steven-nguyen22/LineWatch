import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const ODDS_API_KEY = Deno.env.get("ODDS_API_KEY")!;
const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

Deno.serve(async (_req) => {
  try {
    // Fetch NHL odds from the-odds-api
    const url = `https://api.the-odds-api.com/v4/sports/icehockey_nhl/odds/?apiKey=${ODDS_API_KEY}&regions=us&markets=h2h,spreads,totals&oddsFormat=american`;
    const res = await fetch(url);

    if (!res.ok) {
      const body = await res.text();
      return new Response(
        JSON.stringify({ error: "Odds API error", status: res.status, body }),
        { status: 502, headers: { "Content-Type": "application/json" } }
      );
    }

    const data = await res.json();

    // Upsert into Supabase cached_odds table
    const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);
    const { error } = await supabase.from("cached_odds").upsert({
      sport_key: "icehockey_nhl",
      data: data,
      updated_at: new Date().toISOString(),
    });

    if (error) {
      return new Response(JSON.stringify({ error: error.message }), {
        status: 500,
        headers: { "Content-Type": "application/json" },
      });
    }

    return new Response(
      JSON.stringify({ success: true, events: data.length }),
      { status: 200, headers: { "Content-Type": "application/json" } }
    );
  } catch (err) {
    return new Response(
      JSON.stringify({ error: String(err) }),
      { status: 500, headers: { "Content-Type": "application/json" } }
    );
  }
});
