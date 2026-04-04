import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

// ESPN team name → ESPN numeric team ID mapping
const NHL_TEAM_IDS: Record<string, number> = {
  "Anaheim Ducks": 25,
  "Boston Bruins": 1,
  "Buffalo Sabres": 2,
  "Calgary Flames": 3,
  "Carolina Hurricanes": 7,
  "Chicago Blackhawks": 4,
  "Colorado Avalanche": 17,
  "Columbus Blue Jackets": 29,
  "Dallas Stars": 9,
  "Detroit Red Wings": 5,
  "Edmonton Oilers": 6,
  "Florida Panthers": 26,
  "Los Angeles Kings": 8,
  "Minnesota Wild": 30,
  "Montreal Canadiens": 10,
  "Nashville Predators": 27,
  "New Jersey Devils": 11,
  "New York Islanders": 12,
  "New York Rangers": 13,
  "Ottawa Senators": 14,
  "Philadelphia Flyers": 15,
  "Pittsburgh Penguins": 16,
  "San Jose Sharks": 18,
  "Seattle Kraken": 124292,
  "St. Louis Blues": 19,
  "Tampa Bay Lightning": 20,
  "Toronto Maple Leafs": 21,
  "Utah Hockey Club": 129764,
  "Vancouver Canucks": 22,
  "Vegas Golden Knights": 37,
  "Washington Capitals": 23,
  "Winnipeg Jets": 28,
};

// Aliases used by The Odds API
const TEAM_ALIASES: Record<string, number> = {
  "Montréal Canadiens": 10,
  "St Louis Blues": 19,
  "Utah Mammoth": 129764,
};

interface ESPNAthlete {
  id: string;
  displayName: string;
  headshot?: { href: string };
}

Deno.serve(async (_req) => {
  try {
    const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);

    // Step 1: Populate nhl_teams with all 32 teams + aliases
    const teamRows = [
      ...Object.entries(NHL_TEAM_IDS),
      ...Object.entries(TEAM_ALIASES),
    ].map(([name, espnId]) => ({
      team_name: name,
      espn_id: espnId,
      logo_url: `https://a.espncdn.com/i/teamlogos/nhl/500/${espnId}.png`,
    }));

    const { error: teamError } = await supabase
      .from("nhl_teams")
      .upsert(teamRows, { onConflict: "team_name" });

    if (teamError) {
      return new Response(
        JSON.stringify({ error: "Failed to upsert teams", detail: teamError.message }),
        { status: 500, headers: { "Content-Type": "application/json" } }
      );
    }

    // Step 2: Fetch rosters from ESPN for all 32 teams (unique IDs only)
    const uniqueTeamEntries = Object.entries(NHL_TEAM_IDS);
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
        const rosterUrl = `https://site.api.espn.com/apis/site/v2/sports/hockey/nhl/teams/${espnId}/roster`;
        const res = await fetch(rosterUrl);

        if (!res.ok) {
          failedTeams++;
          continue;
        }

        const data = await res.json();

        // ESPN NHL rosters use nested position groups (Centers, Wings, Defensemen, Goalies)
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
          const headshotUrl =
            athlete.headshot?.href ||
            `https://a.espncdn.com/i/headshots/nhl/players/full/${athlete.id}.png`;

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
          .from("nhl_players")
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
      .from("nhl_players")
      .select("id,player_name,team_name");

    if (existingPlayers) {
      const staleIds = existingPlayers
        .filter((p) => !currentPlayerKeys.has(`${p.player_name}|${p.team_name}`))
        .map((p) => p.id);

      if (staleIds.length > 0) {
        await supabase.from("nhl_players").delete().in("id", staleIds);
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
