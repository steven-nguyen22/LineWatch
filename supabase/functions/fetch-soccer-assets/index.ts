import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

// ESPN team name → ESPN numeric team ID mapping
// Team names match The Odds API format for UEFA Champions League
// NOTE: UCL participants change each season — update this mapping yearly
const SOCCER_TEAM_IDS: Record<string, number> = {
  // England
  "Arsenal": 359,
  "Aston Villa": 362,
  "Liverpool": 364,
  "Manchester City": 382,
  "Manchester United": 360,
  "Chelsea": 363,
  "Tottenham Hotspur": 367,
  // Spain
  "Barcelona": 83,
  "Real Madrid": 86,
  "Atletico Madrid": 1068,
  "Girona": 9812,
  // Germany
  "Bayern Munich": 132,
  "Borussia Dortmund": 124,
  "RB Leipzig": 11420,
  "Bayer Leverkusen": 131,
  "VfB Stuttgart": 134,
  // Italy
  "AC Milan": 103,
  "Inter Milan": 110,
  "Juventus": 111,
  "Atalanta": 102,
  "Bologna": 107,
  // France
  "Paris Saint-Germain": 160,
  "Monaco": 174,
  "Brest": 1417,
  "Lille": 166,
  // Portugal
  "Benfica": 1864,
  "Sporting CP": 2010,
  "Porto": 1903,
  // Netherlands
  "PSV Eindhoven": 148,
  "Feyenoord": 143,
  // Others
  "Celtic": 285,
  "Club Brugge": 2356,
  "Red Star Belgrade": 2047,
  "Young Boys": 3054,
  "Salzburg": 3003,
  "Shakhtar Donetsk": 3040,
  "Dinamo Zagreb": 2585,
  "Slovan Bratislava": 3061,
  "Sturm Graz": 2999,
  "Sparta Prague": 2962,
};

// Aliases used by The Odds API that map to the same ESPN IDs
const TEAM_ALIASES: Record<string, number> = {
  "Atlético Madrid": 1068,
  "Internazionale": 110,
  "Paris Saint Germain": 160,
  "PSG": 160,
  "PSV": 148,
  "Sporting Lisbon": 2010,
  "Red Bull Salzburg": 3003,
  "Crvena Zvezda": 2047,
  "GNK Dinamo Zagreb": 2585,
  "Sparta Praha": 2962,
};

// Each team's domestic league ESPN endpoint slug
// NOTE: ESPN uses "esp.1" for La Liga (not "spa.1")
const TEAM_LEAGUE: Record<string, string> = {
  // England
  "Arsenal": "eng.1",
  "Aston Villa": "eng.1",
  "Liverpool": "eng.1",
  "Manchester City": "eng.1",
  "Manchester United": "eng.1",
  "Chelsea": "eng.1",
  "Tottenham Hotspur": "eng.1",
  // Spain (ESPN uses "esp.1")
  "Barcelona": "esp.1",
  "Real Madrid": "esp.1",
  "Atletico Madrid": "esp.1",
  "Girona": "esp.1",
  // Germany
  "Bayern Munich": "ger.1",
  "Borussia Dortmund": "ger.1",
  "RB Leipzig": "ger.1",
  "Bayer Leverkusen": "ger.1",
  "VfB Stuttgart": "ger.1",
  // Italy
  "AC Milan": "ita.1",
  "Inter Milan": "ita.1",
  "Juventus": "ita.1",
  "Atalanta": "ita.1",
  "Bologna": "ita.1",
  // France
  "Paris Saint-Germain": "fra.1",
  "Monaco": "fra.1",
  "Brest": "fra.1",
  "Lille": "fra.1",
  // Portugal
  "Benfica": "por.1",
  "Sporting CP": "por.1",
  "Porto": "por.1",
  // Netherlands
  "PSV Eindhoven": "ned.1",
  "Feyenoord": "ned.1",
  // Others
  "Celtic": "sco.1",
  "Club Brugge": "bel.1",
  "Red Star Belgrade": "srb.1",
  "Young Boys": "sui.1",
  "Salzburg": "aut.1",
  "Shakhtar Donetsk": "ukr.1",
  "Dinamo Zagreb": "cro.1",
  "Slovan Bratislava": "svk.1",
  "Sturm Graz": "aut.1",
  "Sparta Prague": "cze.1",
};

interface ESPNAthlete {
  id: string;
  displayName: string;
  headshot?: { href: string };
}

// Headshot URLs starting with this prefix are broken ESPN fallbacks that need replacing
const ESPN_HEADSHOT_PREFIX = "https://a.espncdn.com/i/headshots/soccer/players/full/";

/**
 * Search TheSportsDB for a player headshot (cutout or thumb).
 * Returns:
 *   - URL string if found
 *   - "none" if the API responded successfully but the player doesn't exist
 *   - null if the request failed (rate limit, network error) — caller should retry later
 */
async function searchHeadshot(playerName: string): Promise<string | "none" | null> {
  try {
    const url = `https://www.thesportsdb.com/api/v1/json/3/searchplayers.php?p=${encodeURIComponent(playerName)}`;
    const res = await fetch(url);

    // Non-200 means rate limit or server error — return null so we retry later
    if (!res.ok) return null;

    const data = await res.json();
    // deno-lint-ignore no-explicit-any
    const players: any[] = data.player || [];

    if (players.length === 0) {
      // Successful response but player not found — genuinely missing
      return "none";
    }

    // Prefer cutout (transparent background) over thumb (full photo)
    return players[0].strCutout || players[0].strThumb || "none";
  } catch {
    // Network error — return null so we retry later
    return null;
  }
}

Deno.serve(async (req) => {
  // Auth check
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

  const url = new URL(req.url);
  const step = url.searchParams.get("step") || "rosters";

  try {
    const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);

    // ─── STEP 1: "rosters" (default) ───────────────────────────────────
    // Fetches ESPN rosters, upserts teams + players.
    // Headshot URLs are set to ESPN fallback (which are mostly broken for soccer).
    // Run this first, then run step=headshots to fix them.
    if (step === "rosters") {
      // Upsert teams
      const teamRows = [
        ...Object.entries(SOCCER_TEAM_IDS),
        ...Object.entries(TEAM_ALIASES),
      ].map(([name, espnId]) => ({
        team_name: name,
        espn_id: espnId,
        logo_url: `https://a.espncdn.com/i/teamlogos/soccer/500/${espnId}.png`,
      }));

      const { error: teamError } = await supabase
        .from("soccer_teams")
        .upsert(teamRows, { onConflict: "team_name" });

      if (teamError) {
        return new Response(
          JSON.stringify({ error: "Failed to upsert teams", detail: teamError.message }),
          { status: 500, headers: { "Content-Type": "application/json" } }
        );
      }

      // Fetch rosters from ESPN
      const uniqueTeamEntries = Object.entries(SOCCER_TEAM_IDS);
      let totalPlayers = 0;
      let failedTeams = 0;

      const allPlayerRows: {
        player_name: string;
        espn_id: number;
        headshot_url: string;
        team_name: string;
      }[] = [];

      for (const [teamName, espnId] of uniqueTeamEntries) {
        try {
          let res = await fetch(
            `https://site.api.espn.com/apis/site/v2/sports/soccer/uefa.champions/teams/${espnId}/roster`
          );

          if (!res.ok) {
            const league = TEAM_LEAGUE[teamName] ?? "eng.1";
            res = await fetch(
              `https://site.api.espn.com/apis/site/v2/sports/soccer/${league}/teams/${espnId}/roster`
            );
          }

          if (!res.ok) {
            failedTeams++;
            continue;
          }

          const data = await res.json();

          const athletes: ESPNAthlete[] = [];
          if (Array.isArray(data.athletes)) {
            for (const item of data.athletes) {
              if (Array.isArray(item.items)) {
                for (const athlete of item.items) {
                  if (athlete.id && athlete.displayName) {
                    athletes.push({
                      id: String(athlete.id),
                      displayName: athlete.displayName,
                      headshot: athlete.headshot,
                    });
                  }
                }
              } else if (item.id && item.displayName) {
                athletes.push({
                  id: String(item.id),
                  displayName: item.displayName,
                  headshot: item.headshot,
                });
              }
            }
          }

          for (const athlete of athletes) {
            const espnHeadshot = athlete.headshot?.href || null;
            allPlayerRows.push({
              player_name: athlete.displayName,
              espn_id: parseInt(athlete.id, 10),
              headshot_url: espnHeadshot || `${ESPN_HEADSHOT_PREFIX}${athlete.id}.png`,
              team_name: teamName,
            });
          }

          await new Promise((resolve) => setTimeout(resolve, 200));
        } catch {
          failedTeams++;
        }
      }

      // Upsert players in batches of 100
      if (allPlayerRows.length > 0) {
        for (let i = 0; i < allPlayerRows.length; i += 100) {
          const batch = allPlayerRows.slice(i, i + 100);
          await supabase
            .from("soccer_players")
            .upsert(batch, { onConflict: "player_name,team_name" });
        }
        totalPlayers = allPlayerRows.length;
      }

      // Clean up stale players
      const currentPlayerKeys = new Set(
        allPlayerRows.map((p) => `${p.player_name}|${p.team_name}`)
      );
      const { data: existingPlayers } = await supabase
        .from("soccer_players")
        .select("id,player_name,team_name");

      if (existingPlayers) {
        const staleIds = existingPlayers
          .filter((p) => !currentPlayerKeys.has(`${p.player_name}|${p.team_name}`))
          .map((p) => p.id);
        if (staleIds.length > 0) {
          await supabase.from("soccer_players").delete().in("id", staleIds);
        }
      }

      // Count how many players still need headshots
      const { count: needHeadshots } = await supabase
        .from("soccer_players")
        .select("id", { count: "exact", head: true })
        .like("headshot_url", `${ESPN_HEADSHOT_PREFIX}%`);

      return new Response(
        JSON.stringify({
          success: true,
          step: "rosters",
          teams: teamRows.length,
          players: totalPlayers,
          failed_teams: failedTeams,
          players_needing_headshots: needHeadshots ?? 0,
          next: "Run again with ?step=headshots to fetch images from TheSportsDB (call repeatedly until remaining=0)",
        }),
        { status: 200, headers: { "Content-Type": "application/json" } }
      );
    }

    // ─── STEP 2: "headshots" ──────────────────────────────────────────
    // Reads up to 25 players with broken ESPN headshot URLs from the DB,
    // searches TheSportsDB for each, and updates the row.
    // Call repeatedly until remaining = 0.
    if (step === "headshots") {
      const BATCH_SIZE = 25;

      // Get players that still have the broken ESPN CDN headshot URL
      const { data: players, error: fetchError } = await supabase
        .from("soccer_players")
        .select("id,player_name,espn_id")
        .like("headshot_url", `${ESPN_HEADSHOT_PREFIX}%`)
        .limit(BATCH_SIZE);

      if (fetchError) {
        return new Response(
          JSON.stringify({ error: "Failed to fetch players", detail: fetchError.message }),
          { status: 500, headers: { "Content-Type": "application/json" } }
        );
      }

      if (!players || players.length === 0) {
        return new Response(
          JSON.stringify({ success: true, step: "headshots", updated: 0, remaining: 0, done: true }),
          { status: 200, headers: { "Content-Type": "application/json" } }
        );
      }

      let updated = 0;
      let notFound = 0;
      let rateLimited = 0;

      for (const player of players) {
        const result = await searchHeadshot(player.player_name);

        if (result && result !== "none") {
          // Found a headshot URL — save it
          await supabase
            .from("soccer_players")
            .update({ headshot_url: result })
            .eq("id", player.id);
          updated++;
        } else if (result === "none") {
          // TheSportsDB confirmed player doesn't exist — mark permanently
          await supabase
            .from("soccer_players")
            .update({ headshot_url: "none" })
            .eq("id", player.id);
          notFound++;
        } else {
          // null = rate limited or network error — leave ESPN URL so we retry next call
          rateLimited++;
        }

        // Rate limit — 1s between TheSportsDB requests to avoid throttling
        await new Promise((resolve) => setTimeout(resolve, 1000));
      }

      // Count how many still remain
      const { count: remaining } = await supabase
        .from("soccer_players")
        .select("id", { count: "exact", head: true })
        .like("headshot_url", `${ESPN_HEADSHOT_PREFIX}%`);

      return new Response(
        JSON.stringify({
          success: true,
          step: "headshots",
          processed: players.length,
          updated,
          not_found: notFound,
          rate_limited: rateLimited,
          remaining: remaining ?? 0,
          done: (remaining ?? 0) === 0,
        }),
        { status: 200, headers: { "Content-Type": "application/json" } }
      );
    }

    // ─── STEP 3: "retry" ────────────────────────────────────────────
    // Resets players marked "none" back to ESPN fallback URL so they
    // get retried on the next ?step=headshots call.
    // Use this after the initial run if many were rate-limited.
    if (step === "retry") {
      const { count: noneCount } = await supabase
        .from("soccer_players")
        .select("id", { count: "exact", head: true })
        .eq("headshot_url", "none");

      // Reset "none" back to ESPN fallback so headshots step will retry them
      const { data: nonePlayers } = await supabase
        .from("soccer_players")
        .select("id,espn_id")
        .eq("headshot_url", "none");

      if (nonePlayers && nonePlayers.length > 0) {
        for (const p of nonePlayers) {
          await supabase
            .from("soccer_players")
            .update({ headshot_url: `${ESPN_HEADSHOT_PREFIX}${p.espn_id}.png` })
            .eq("id", p.id);
        }
      }

      return new Response(
        JSON.stringify({
          success: true,
          step: "retry",
          reset_count: noneCount ?? 0,
          next: "Now run ?step=headshots repeatedly to retry these players",
        }),
        { status: 200, headers: { "Content-Type": "application/json" } }
      );
    }

    return new Response(
      JSON.stringify({ error: "Unknown step. Use ?step=rosters, ?step=headshots, or ?step=retry" }),
      { status: 400, headers: { "Content-Type": "application/json" } }
    );
  } catch (err) {
    return new Response(
      JSON.stringify({ error: String(err) }),
      { status: 500, headers: { "Content-Type": "application/json" } }
    );
  }
});
