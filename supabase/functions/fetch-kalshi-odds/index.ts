import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { MLB_TEAMS, NBA_TEAMS, NFL_TEAMS, NHL_TEAMS } from "./team-maps.ts";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

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

// Real Kalshi market shape (from live API inspection)
interface KalshiMarket {
  ticker: string;
  event_ticker?: string;      // e.g. "KXNBAGAME-26APR25OKCPHX"
  yes_sub_title?: string;     // e.g. "Phoenix" — the YES team city/nickname
  no_sub_title?: string;      // e.g. "Oklahoma City"
  title?: string;
  yes_ask_dollars?: string;   // e.g. "0.1800" — implied prob, already 0-1
  no_ask_dollars?: string;    // e.g. "0.8500"
  status?: string;
  occurrence_datetime?: string;
}

interface KalshiListResponse {
  markets?: KalshiMarket[];
  cursor?: string;
}

/**
 * Convert an implied probability (0-1) into American odds.
 * p >= 0.5 → favorite (negative); p < 0.5 → underdog (positive).
 */
function probToAmerican(p: number): number {
  if (!Number.isFinite(p) || p <= 0 || p >= 1) return 0;
  if (p >= 0.5) return Math.round(-(p / (1 - p)) * 100);
  return Math.round(((1 - p) / p) * 100);
}

/**
 * Parse a Kalshi event_ticker like "KXNBAGAME-26APR25OKCPHX" into
 * { isoDate, awayAbbr, homeAbbr }.
 * The event_ticker has no trailing team suffix (unlike individual market tickers).
 */
function parseEventTicker(
  eventTicker: string,
  teams: Record<string, string>,
): { isoDate: string; awayAbbr: string; homeAbbr: string } | null {
  const dash = eventTicker.indexOf("-");
  if (dash < 0) return null;
  const suffix = eventTicker.slice(dash + 1); // e.g. "26APR25OKCPHX"

  // Optional 4-digit time component between day and team codes (e.g. MLB "1610")
  const m = suffix.match(/^(\d{2})([A-Z]{3})(\d{2})\d{0,4}([A-Z]{4,8})$/);
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
 * Fetch all active markets for a Kalshi series, paginating via cursor.
 * Uses status=active (not "open") — confirmed from live API inspection.
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

/**
 * Deduplicate markets by event_ticker and transform each game into a
 * single TransformedEvent with both team outcomes.
 *
 * Each game has two Kalshi markets (one per team as YES). We group by
 * event_ticker and use whichever market we see first — it already has
 * yes_ask_dollars for one team and no_ask_dollars for the other.
 *
 * yes_sub_title / no_sub_title give us city/nickname strings ("Phoenix",
 * "Oklahoma City") so we match them against the last token(s) of the
 * full team names from our map to identify which side is which.
 */
function transformMarkets(
  markets: KalshiMarket[],
  teams: Record<string, string>,
  nowIso: string,
): TransformedEvent[] {
  // Deduplicate: one entry per event_ticker
  const seen = new Map<string, KalshiMarket>();
  for (const m of markets) {
    const key = m.event_ticker ?? m.ticker;
    if (!seen.has(key)) seen.set(key, m);
  }

  const out: TransformedEvent[] = [];

  for (const [eventTicker, market] of seen) {
    const parsed = parseEventTicker(eventTicker, teams);
    if (!parsed) continue;

    const awayName = teams[parsed.awayAbbr];
    const homeName = teams[parsed.homeAbbr];
    if (!awayName || !homeName) continue;

    const yesAskStr = market.yes_ask_dollars;
    const noAskStr = market.no_ask_dollars;
    if (!yesAskStr || !noAskStr) continue;

    const yesProb = parseFloat(yesAskStr);
    const noProb = parseFloat(noAskStr);
    if (!Number.isFinite(yesProb) || !Number.isFinite(noProb)) continue;
    if (yesProb <= 0 || noProb <= 0) continue;

    // Determine which team YES refers to using yes_sub_title + no_sub_title.
    // Kalshi uses city names ("Phoenix"), nicknames ("Lightning"), or
    // informal names ("A's") — check both sub_titles so that even if the
    // YES side is unrecognizable (e.g. "A's"), the NO side ("Seattle")
    // still identifies the layout unambiguously.
    //
    // awayIsYes is true when:
    //   (a) yes_sub_title matches away team name, OR
    //   (b) no_sub_title matches home team name (home is NO → away is YES)
    const yesSub = (market.yes_sub_title ?? "").toLowerCase().trim();
    const noSub  = (market.no_sub_title  ?? "").toLowerCase().trim();

    const subMatchesTeam = (sub: string, teamName: string): boolean => {
      if (!sub) return false;
      const t = teamName.toLowerCase();
      if (t.includes(sub)) return true;
      return t.split(/\s+/).some((tok) => tok.length > 3 && sub.includes(tok));
    };

    const awayIsYes = subMatchesTeam(yesSub, awayName) || subMatchesTeam(noSub, homeName);
    const homeIsYes = subMatchesTeam(yesSub, homeName) || subMatchesTeam(noSub, awayName);

    let awayProb: number, homeProb: number;
    if (awayIsYes && !homeIsYes) {
      awayProb = yesProb;
      homeProb = noProb;
    } else if (homeIsYes && !awayIsYes) {
      homeProb = yesProb;
      awayProb = noProb;
    } else {
      // Ambiguous or no match — skip
      continue;
    }

    const awayPrice = probToAmerican(awayProb);
    const homePrice = probToAmerican(homeProb);
    if (awayPrice === 0 || homePrice === 0) continue;

    out.push({
      id: eventTicker,
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
    });
  }

  return out;
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

      const transformed = transformMarkets(result.value, sport.teams, nowIso);

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
