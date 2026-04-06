import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

const GOLF_SPORT_KEYS = [
  "golf_masters_tournament_winner",
  "golf_pga_championship_winner",
  "golf_the_open_championship_winner",
  "golf_us_open_winner",
];

const STALE_DAYS = 30;

// deno-lint-ignore no-explicit-any
interface CachedOddsRow {
  data: any[];
}

interface ExistingRow {
  golfer_name: string;
  updated_at: string;
}

interface SearchItem {
  displayName?: string;
  sport?: string;
  headshot?: { href?: string };
}

function sleep(ms: number): Promise<void> {
  return new Promise((r) => setTimeout(r, ms));
}

async function lookupHeadshot(name: string): Promise<string | null> {
  const url = `https://site.web.api.espn.com/apis/common/v3/search?query=${encodeURIComponent(name)}&limit=5&type=player`;
  const res = await fetch(url);
  if (!res.ok) return null;
  const body = await res.json();
  const items: SearchItem[] = body.items ?? [];
  // Prefer exact name match for golf, then any golf result with a headshot
  const hit =
    items.find(
      (i) =>
        i.sport === "golf" &&
        i.headshot?.href &&
        i.displayName?.toLowerCase() === name.toLowerCase()
    ) ?? items.find((i) => i.sport === "golf" && i.headshot?.href);
  return hit?.headshot?.href ?? null;
}

Deno.serve(async (req) => {
  // Auth check
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
    const staleCutoff = new Date(
      Date.now() - STALE_DAYS * 86400 * 1000
    ).toISOString();

    // 1. Collect all unique golfer names from cached_odds outrights
    const allNames = new Set<string>();

    for (const sportKey of GOLF_SPORT_KEYS) {
      const { data: oddsRows, error: oddsErr } = await supabase
        .from("cached_odds")
        .select("data")
        .eq("sport_key", sportKey)
        .limit(1);

      if (oddsErr) {
        return new Response(
          JSON.stringify({ error: oddsErr.message, sport_key: sportKey }),
          { status: 500, headers: { "Content-Type": "application/json" } }
        );
      }

      const events = (oddsRows?.[0] as CachedOddsRow | undefined)?.data ?? [];
      for (const event of events) {
        const bookmakers = event.bookmakers ?? [];
        for (const bookmaker of bookmakers) {
          const markets = bookmaker.markets ?? [];
          for (const market of markets) {
            if (market.key !== "outrights") continue;
            const outcomes = market.outcomes ?? [];
            for (const outcome of outcomes) {
              if (outcome.name) {
                allNames.add(outcome.name);
              }
            }
          }
        }
      }
    }

    if (allNames.size === 0) {
      return new Response(
        JSON.stringify({
          success: true,
          golfers_found: 0,
          queried: 0,
          matched: 0,
        }),
        { status: 200, headers: { "Content-Type": "application/json" } }
      );
    }

    // 2. Find which names we already cached recently
    const { data: existing, error: existErr } = await supabase
      .from("golfer_headshots")
      .select("golfer_name, updated_at")
      .in("golfer_name", Array.from(allNames));

    if (existErr) {
      return new Response(JSON.stringify({ error: existErr.message }), {
        status: 500,
        headers: { "Content-Type": "application/json" },
      });
    }

    const fresh = new Set(
      ((existing as ExistingRow[] | null) ?? [])
        .filter((r) => r.updated_at > staleCutoff)
        .map((r) => r.golfer_name)
    );

    const toLookup = Array.from(allNames).filter((n) => !fresh.has(n));

    // 3. Query ESPN for each stale/unknown golfer
    let matched = 0;
    for (let i = 0; i < toLookup.length; i++) {
      const name = toLookup[i];
      const headshotUrl = await lookupHeadshot(name);
      if (headshotUrl) matched++;

      const { error: upsertErr } = await supabase
        .from("golfer_headshots")
        .upsert({
          golfer_name: name,
          headshot_url: headshotUrl,
          updated_at: new Date().toISOString(),
        });

      if (upsertErr) {
        return new Response(
          JSON.stringify({ error: upsertErr.message, name }),
          { status: 500, headers: { "Content-Type": "application/json" } }
        );
      }

      if (i < toLookup.length - 1) await sleep(200);
    }

    return new Response(
      JSON.stringify({
        success: true,
        golfers_found: allNames.size,
        already_fresh: fresh.size,
        queried: toLookup.length,
        matched,
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
