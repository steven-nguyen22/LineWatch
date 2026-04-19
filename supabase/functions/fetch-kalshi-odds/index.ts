import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { MLB_TEAMS, NBA_TEAMS, NFL_TEAMS, NHL_TEAMS } from "./team-maps.ts";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

// Kalshi game series + the sport_key we cache under + the abbrev→name map.
// All four series are public (no auth) on Kalshi's elections gateway.
const SPORTS = [
  { series: "KXNBAGAME",  cacheKey: "kalshi_basketball_nba",       teams: NBA_TEAMS },
  { series: "KXNFLGAME",  cacheKey: "kalshi_americanfootball_nfl", teams: NFL_TEAMS },
  { series: "KXMLBGAME",  cacheKey: "kalshi_baseball_mlb",         teams: MLB_TEAMS },
  { series: "KXNHLGAME",  cacheKey: "kalshi_icehockey_nhl",        teams: NHL_TEAMS },
] as const;

const MONTHS: Record<string, string> = {
  JAN: "01", FEB: "02", MAR: "03", APR: "04", MAY: "05", JUN: "06",
  JUL: "07", AUG: "08", SEP: "09", OCT: "10", NOV: "11", DEC: "12",
};

interface KalshiMarket {
  ticker: string;
  event_ticker?: string;
  yes_sub_title?: string;
  no_sub_title?: string;
  title?: string;
  yes_ask?: number;     // cents (0-100)
  no_ask?: number;
  status?: string;
  close_time?: string;
  expected_expiration_time?: string;
}

interface KalshiListResponse {
  markets?: KalshiMarket[];
  cursor?: string;
}

/**
 * Convert an implied probability (0-1 ask price, where the ask is what
 * a buyer pays to acquire a $1 YES contract) into American odds.
 *
 *   p ≥ 0.5 → favorite (negative); p < 0.5 → underdog (positive)
 */
function probToAmerican(p: number): number {
  if (!Number.isFinite(p) || p <= 0 || p >= 1) return 0;
  if (p >= 0.5) return Math.round(-(p / (1 - p)) * 100);
  return Math.round(((1 - p) / p) * 100);
}

/**
 * Parse a Kalshi game ticker like `KXNBAGAME-26APR15ORLPHI` into
 *   { isoDate: "2026-04-15", awayAbbr: "ORL", homeAbbr: "PHI" }
 *
 * Kalshi's convention within a given series is that the first abbr is
 * the away team and the second is the home team. We resolve which team
 * is YES by matching `yes_sub_title` against the two candidate names.
 *
 * Abbreviations are variable length (2-4 chars), so we find the split
 * by trying each prefix length in [2,3,4] and checking membership in
 * the team map.
 */
function parseTicker(
  ticker: string,
  teams: Record<string, string>,
): { isoDate: string; awayAbbr: string; homeAbbr: string } | null {
  // Example suffix: "26APR15ORLPHI"
  const dash = ticker.indexOf("-");
  if (dash < 0) return null;
  const suffix = ticker.slice(dash + 1);

  // YYMMM DD then the two team codes
  const m = suffix.match(/^(\d{2})([A-Z]{3})(\d{2})([A-Z]{4,8})$/);
  if (!m) return null;
  const [, yy, monAbbr, dd, teamsPart] = m;
  const mm = MONTHS[monAbbr];
  if (!mm) return null;
  const isoDate = `20${yy}-${mm}-${dd}`;

  // teamsPart is away+home concatenated, each 2-4 chars. Try splits.
  for (const awayLen of [4, 3, 2]) {
    const homeLen = teamsPart.length - awayLen;
    if (homeLen < 2 || homeLen > 4) continue;
    const awayAbbr = teamsPart.slice(0, awayLen);
    const homeAbbr = teamsPart.slice(awayLen);
    if (teams[awayAbbr] && teams[homeAbbr]) {
      return { isoDate, awayAbbr, homeAbbr };
    }
  }
  return null;
}

/**
 * Decide which of { away, home } the YES contract refers to, using
 * `yes_sub_title` or `title` heuristics. Returns "away" | "home" | null.
 */
function whichSideIsYes(
  market: KalshiMarket,
  awayName: string,
  homeName: string,
): "away" | "home" | null {
  const haystacks = [market.yes_sub_title, market.title].filter(Boolean) as string[];
  for (const s of haystacks) {
    const lower = s.toLowerCase();
    const awayTokens = awayName.toLowerCase().split(/\s+/);
    const homeTokens = homeName.toLowerCase().split(/\s+/);

    // The nickname (last token) is the most reliable signal.
    const awayNick = awayTokens[awayTokens.length - 1];
    const homeNick = homeTokens[homeTokens.length - 1];
    const awayHit = lower.includes(awayNick);
    const homeHit = lower.includes(homeNick);
    if (awayHit && !homeHit) return "away";
    if (homeHit && !awayHit) return "home";
  }
  return null;
}

/**
 * Fetch every open market for a Kalshi series, paginating via `cursor`.
 */
async function fetchAllMarkets(series: string): Promise<KalshiMarket[]> {
  const out: KalshiMarket[] = [];
  let cursor = "";
  for (let i = 0; i < 20; i++) {
    const url = new URL("https://api.elections.kalshi.com/trade-api/v2/markets");
    url.searchParams.set("series_ticker", series);
    url.searchParams.set("status", "open");
    url.searchParams.set("limit", "1000");
    if (cursor) url.searchParams.set("cursor", cursor);

    const res = await fetch(url.toString());
    if (!res.ok) throw new Error(`Kalshi ${series} HTTP ${res.status}`);
    const body = (await res.json()) as KalshiListResponse;
    if (body.markets?.length) out.push(...body.markets);
    if (!body.cursor) break;
    cursor = body.cursor;
  }
  return out;
}

interface TransformedEvent {
  id: string;
  commence_date: string;
  away_team: string;
  home_team: string;
  bookmaker: {
    key: string;
    title: string;
    last_update: string;
    markets: Array<{
      key: string;
      last_update: string;
      outcomes: Array<{ name: string; price: number }>;
    }>;
  };
}

function transformMarket(
  market: KalshiMarket,
  teams: Record<string, string>,
  nowIso: string,
): TransformedEvent | null {
  const parsed = parseTicker(market.ticker, teams);
  if (!parsed) return null;
  const awayName = teams[parsed.awayAbbr];
  const homeName = teams[parsed.homeAbbr];
  if (!awayName || !homeName) return null;

  // Kalshi returns ask prices in cents (integer 1-99). Both sides required.
  const yesCents = market.yes_ask;
  const noCents = market.no_ask;
  if (!yesCents || !noCents || yesCents <= 0 || noCents <= 0) return null;
  const yesProb = yesCents / 100;
  const noProb = noCents / 100;

  const yesSide = whichSideIsYes(market, awayName, homeName);
  if (!yesSide) return null;

  const awayProb = yesSide === "away" ? yesProb : noProb;
  const homeProb = yesSide === "home" ? yesProb : noProb;

  const awayPrice = probToAmerican(awayProb);
  const homePrice = probToAmerican(homeProb);
  if (awayPrice === 0 || homePrice === 0) return null;

  return {
    id: market.ticker,
    commence_date: parsed.isoDate,
    away_team: awayName,
    home_team: homeName,
    bookmaker: {
      key: "kalshi",
      title: "Kalshi",
      last_update: nowIso,
      markets: [
        {
          key: "h2h",
          last_update: nowIso,
          outcomes: [
            { name: awayName, price: awayPrice },
            { name: homeName, price: homePrice },
          ],
        },
      ],
    },
  };
}

Deno.serve(async (req) => {
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
    const nowIso = new Date().toISOString();

    // Fetch all 4 series in parallel.
    const results = await Promise.allSettled(
      SPORTS.map((s) => fetchAllMarkets(s.series)),
    );

    const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);
    const counts: Record<string, number> = {};
    const errors: Record<string, string> = {};

    for (let i = 0; i < SPORTS.length; i++) {
      const sport = SPORTS[i];
      const result = results[i];
      if (result.status === "rejected") {
        errors[sport.series] = String(result.reason);
        continue;
      }

      const transformed: TransformedEvent[] = [];
      for (const market of result.value) {
        try {
          const ev = transformMarket(market, sport.teams, nowIso);
          if (ev) transformed.push(ev);
        } catch {
          // Per-market parse failure: skip, continue.
        }
      }

      const { error } = await supabase.from("cached_odds").upsert({
        sport_key: sport.cacheKey,
        data: transformed,
        updated_at: nowIso,
      });
      if (error) {
        errors[sport.series] = error.message;
      } else {
        counts[sport.series] = transformed.length;
      }
    }

    return new Response(
      JSON.stringify({ success: true, counts, errors }),
      { status: 200, headers: { "Content-Type": "application/json" } },
    );
  } catch (err) {
    return new Response(JSON.stringify({ error: String(err) }), {
      status: 500,
      headers: { "Content-Type": "application/json" },
    });
  }
});
