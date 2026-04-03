import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

// ESPN team name → ESPN numeric team ID mapping
// Team names match The Odds API format
const MLB_TEAM_IDS: Record<string, number> = {
  "Arizona Diamondbacks": 29,
  "Atlanta Braves": 15,
  "Baltimore Orioles": 1,
  "Boston Red Sox": 2,
  "Chicago Cubs": 16,
  "Chicago White Sox": 4,
  "Cincinnati Reds": 17,
  "Cleveland Guardians": 5,
  "Colorado Rockies": 27,
  "Detroit Tigers": 6,
  "Houston Astros": 18,
  "Kansas City Royals": 7,
  "Los Angeles Angels": 3,
  "Los Angeles Dodgers": 19,
  "Miami Marlins": 28,
  "Milwaukee Brewers": 8,
  "Minnesota Twins": 9,
  "New York Mets": 21,
  "New York Yankees": 10,
  "Oakland Athletics": 11,
  "Philadelphia Phillies": 22,
  "Pittsburgh Pirates": 23,
  "San Diego Padres": 25,
  "San Francisco Giants": 26,
  "Seattle Mariners": 12,
  "St. Louis Cardinals": 24,
  "Tampa Bay Rays": 30,
  "Texas Rangers": 13,
  "Toronto Blue Jays": 14,
  "Washington Nationals": 20,
};

interface ESPNAthlete {
  id: string;
  displayName: string;
  headshot?: { href: string };
}

Deno.serve(async (_req) => {
  try {
    const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);

    // Step 1: Populate mlb_teams with all 30 teams
    const teamRows = Object.entries(MLB_TEAM_IDS).map(([name, espnId]) => ({
      team_name: name,
      espn_id: espnId,
      logo_url: `https://a.espncdn.com/i/teamlogos/mlb/500/${espnId}.png`,
    }));

    const { error: teamError } = await supabase
      .from("mlb_teams")
      .upsert(teamRows, { onConflict: "team_name" });

    if (teamError) {
      return new Response(
        JSON.stringify({ error: "Failed to upsert teams", detail: teamError.message }),
        { status: 500, headers: { "Content-Type": "application/json" } }
      );
    }

    // Step 2: Fetch rosters from ESPN for all 30 teams
    const uniqueTeamEntries = Object.entries(MLB_TEAM_IDS);
    let totalPlayers = 0;
    let failedTeams = 0;

    // Collect all player rows for bulk upsert
    const allPlayerRows: {
      player_name: string;
      espn_id: number;
      headshot_url: string;
      team_name: string;
    }[] = [];

    for (const [teamName, espnId] of uniqueTeamEntries) {
      try {
        const rosterUrl = `https://site.api.espn.com/apis/site/v2/sports/baseball/mlb/teams/${espnId}/roster`;
        const res = await fetch(rosterUrl);

        if (!res.ok) {
          failedTeams++;
          continue;
        }

        const data = await res.json();

        // ESPN MLB rosters may have athletes as flat array or nested in position groups
        const athletes: ESPNAthlete[] = [];
        if (Array.isArray(data.athletes)) {
          for (const item of data.athletes) {
            // Check if it's a position group with nested items
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
              // Flat array of athletes
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
            `https://a.espncdn.com/i/headshots/mlb/players/full/${athlete.id}.png`;

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
          .from("mlb_players")
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
      .from("mlb_players")
      .select("id,player_name,team_name");

    if (existingPlayers) {
      const staleIds = existingPlayers
        .filter((p) => !currentPlayerKeys.has(`${p.player_name}|${p.team_name}`))
        .map((p) => p.id);

      if (staleIds.length > 0) {
        await supabase.from("mlb_players").delete().in("id", staleIds);
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
