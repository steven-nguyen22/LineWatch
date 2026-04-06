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

interface ESPNAthlete {
  id: string;
  displayName: string;
  headshot?: { href: string };
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

    // Step 1: Populate soccer_teams with all teams + aliases
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

    // Step 2: Fetch rosters from ESPN for all teams (unique IDs only)
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
        // Try UEFA Champions League roster first, fall back to league-specific endpoint
        let res = await fetch(
          `https://site.api.espn.com/apis/site/v2/sports/soccer/uefa.champions/teams/${espnId}/roster`
        );

        if (!res.ok) {
          // Fallback: try the generic football endpoint
          res = await fetch(
            `https://site.api.espn.com/apis/site/v2/sports/soccer/eng.1/teams/${espnId}/roster`
          );
        }

        if (!res.ok) {
          failedTeams++;
          continue;
        }

        const data = await res.json();

        // ESPN soccer rosters use nested position groups (Forwards, Midfielders, Defenders, Goalkeepers)
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
              // Flat array of athletes (fallback)
              athletes.push({
                id: String(item.id),
                displayName: item.displayName,
                headshot: item.headshot,
              });
            }
          }
        }

        for (const athlete of athletes) {
          const headshotUrl =
            athlete.headshot?.href ||
            `https://a.espncdn.com/i/headshots/soccer/players/full/${athlete.id}.png`;

          allPlayerRows.push({
            player_name: athlete.displayName,
            espn_id: parseInt(athlete.id, 10),
            headshot_url: headshotUrl,
            team_name: teamName,
          });
        }

        // Rate limit courtesy — 200ms between ESPN requests
        await new Promise((resolve) => setTimeout(resolve, 200));
      } catch {
        failedTeams++;
      }
    }

    // Step 3: Upsert all players in batches of 100
    if (allPlayerRows.length > 0) {
      for (let i = 0; i < allPlayerRows.length; i += 100) {
        const batch = allPlayerRows.slice(i, i + 100);
        const { error: playerError } = await supabase
          .from("soccer_players")
          .upsert(batch, { onConflict: "player_name,team_name" });

        if (playerError) {
          console.error(`Player upsert batch error: ${playerError.message}`);
        }
      }
      totalPlayers = allPlayerRows.length;
    }

    // Step 4: Clean up players no longer on any roster
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

    return new Response(
      JSON.stringify({
        success: true,
        teams: teamRows.length,
        players: totalPlayers,
        failed_teams: failedTeams,
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
