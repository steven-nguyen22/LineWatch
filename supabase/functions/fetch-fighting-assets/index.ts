import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

const SPORTS = [
  { sport_key: "mma_mixed_martial_arts", espnSport: "mma" },
  { sport_key: "boxing_boxing", espnSport: "boxing" },
] as const;

const STALE_DAYS = 30;

interface CachedOddsRow {
  data: Array<{ home_team?: string; away_team?: string }>;
}

interface ExistingRow {
  fighter_name: string;
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

async function lookupHeadshot(name: string, espnSport: string): Promise<string | null> {
  const url = `https://site.web.api.espn.com/apis/common/v3/search?query=${encodeURIComponent(name)}&limit=5&type=player`;
  const res = await fetch(url);
  if (!res.ok) return null;
  const body = await res.json();
  const items: SearchItem[] = body.items ?? [];
  const hit = items.find(
    (i) => i.sport === espnSport && i.headshot?.href && i.displayName?.toLowerCase() === name.toLowerCase()
  ) ?? items.find((i) => i.sport === espnSport && i.headshot?.href);
  return hit?.headshot?.href ?? null;
}

Deno.serve(async (_req) => {
  try {
    const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);
    const staleCutoff = new Date(Date.now() - STALE_DAYS * 86400 * 1000).toISOString();
    const summary: Record<string, { queried: number; matched: number }> = {};

    for (const sport of SPORTS) {
      // 1. Read cached_odds row for this sport
      const { data: oddsRows, error: oddsErr } = await supabase
        .from("cached_odds")
        .select("data")
        .eq("sport_key", sport.sport_key)
        .limit(1);

      if (oddsErr) {
        return new Response(JSON.stringify({ error: oddsErr.message, sport: sport.sport_key }), {
          status: 500,
          headers: { "Content-Type": "application/json" },
        });
      }

      const events = (oddsRows?.[0] as CachedOddsRow | undefined)?.data ?? [];
      const names = new Set<string>();
      for (const ev of events) {
        if (ev.home_team) names.add(ev.home_team);
        if (ev.away_team) names.add(ev.away_team);
      }

      if (names.size === 0) {
        summary[sport.sport_key] = { queried: 0, matched: 0 };
        continue;
      }

      // 2. Find which names we already cached recently
      const { data: existing, error: existErr } = await supabase
        .from("fighter_headshots")
        .select("fighter_name, updated_at")
        .in("fighter_name", Array.from(names));

      if (existErr) {
        return new Response(JSON.stringify({ error: existErr.message }), {
          status: 500,
          headers: { "Content-Type": "application/json" },
        });
      }

      const fresh = new Set(
        (existing as ExistingRow[] | null ?? [])
          .filter((r) => r.updated_at > staleCutoff)
          .map((r) => r.fighter_name)
      );

      const toLookup = Array.from(names).filter((n) => !fresh.has(n));

      // 3. Query ESPN for each stale/unknown name
      let matched = 0;
      for (let i = 0; i < toLookup.length; i++) {
        const name = toLookup[i];
        const headshotUrl = await lookupHeadshot(name, sport.espnSport);
        if (headshotUrl) matched++;

        const { error: upsertErr } = await supabase.from("fighter_headshots").upsert({
          fighter_name: name,
          headshot_url: headshotUrl,
          sport_key: sport.sport_key,
          updated_at: new Date().toISOString(),
        });

        if (upsertErr) {
          return new Response(JSON.stringify({ error: upsertErr.message, name }), {
            status: 500,
            headers: { "Content-Type": "application/json" },
          });
        }

        if (i < toLookup.length - 1) await sleep(200);
      }

      summary[sport.sport_key] = { queried: toLookup.length, matched };
    }

    return new Response(
      JSON.stringify({
        success: true,
        mma: summary["mma_mixed_martial_arts"] ?? { queried: 0, matched: 0 },
        boxing: summary["boxing_boxing"] ?? { queried: 0, matched: 0 },
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
