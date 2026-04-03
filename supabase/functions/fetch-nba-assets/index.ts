import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

// ESPN team name → ESPN numeric team ID mapping
// Team names match The Odds API format
const NBA_TEAM_IDS: Record<string, number> = {
  "Atlanta Hawks": 1,
  "Boston Celtics": 2,
  "Brooklyn Nets": 17,
  "Charlotte Hornets": 30,
  "Chicago Bulls": 4,
  "Cleveland Cavaliers": 5,
  "Dallas Mavericks": 6,
  "Denver Nuggets": 7,
  "Detroit Pistons": 8,
  "Golden State Warriors": 9,
  "Houston Rockets": 10,
  "Indiana Pacers": 11,
  "Los Angeles Clippers": 12,
  "Los Angeles Lakers": 13,
  "Memphis Grizzlies": 29,
  "Miami Heat": 14,
  "Milwaukee Bucks": 15,
  "Minnesota Timberwolves": 16,
  "New Orleans Pelicans": 3,
  "New York Knicks": 18,
  "Oklahoma City Thunder": 25,
  "Orlando Magic": 19,
  "Philadelphia 76ers": 20,
  "Phoenix Suns": 21,
  "Portland Trail Blazers": 22,
  "Sacramento Kings": 23,
  "San Antonio Spurs": 24,
  "Toronto Raptors": 28,
  "Utah Jazz": 26,
  "Washington Wizards": 27,
};

// Aliases used by The Odds API
const TEAM_ALIASES: Record<string, number> = {
  "LA Clippers": 12,
  "LA Lakers": 13,
};

interface ESPNAthlete {
  id: string;
  displayName: string;
  headshot?: { href: string };
}

Deno.serve(async (_req) => {
  try {
    const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);

    // Step 1: Populate nba_teams with all 30 teams + aliases
    const teamRows = [
      ...Object.entries(NBA_TEAM_IDS),
      ...Object.entries(TEAM_ALIASES),
    ].map(([name, espnId]) => ({
      team_name: name,
      espn_id: espnId,
      logo_url: `https://a.espncdn.com/i/teamlogos/nba/500/${espnId}.png`,
    }));

    const { error: teamError } = await supabase
      .from("nba_teams")
      .upsert(teamRows, { onConflict: "team_name" });

    if (teamError) {
      return new Response(
        JSON.stringify({ error: "Failed to upsert teams", detail: teamError.message }),
        { status: 500, headers: { "Content-Type": "application/json" } }
      );
    }

    // Step 2: Fetch rosters from ESPN for all 30 teams (unique IDs only)
    const uniqueTeamEntries = Object.entries(NBA_TEAM_IDS); // 30 teams, no aliases
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
        const rosterUrl = `https://site.api.espn.com/apis/site/v2/sports/basketball/nba/teams/${espnId}/roster`;
        const res = await fetch(rosterUrl);

        if (!res.ok) {
          failedTeams++;
          continue;
        }

        const data = await res.json();
        const athletes: ESPNAthlete[] = data.athletes || [];

        for (const athlete of athletes) {
          if (!athlete.displayName || !athlete.id) continue;

          const headshotUrl =
            athlete.headshot?.href ||
            `https://a.espncdn.com/i/headshots/nba/players/full/${athlete.id}.png`;

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

    // Step 3: Upsert all players
    if (allPlayerRows.length > 0) {
      // Upsert in batches of 100 to avoid payload limits
      for (let i = 0; i < allPlayerRows.length; i += 100) {
        const batch = allPlayerRows.slice(i, i + 100);
        const { error: playerError } = await supabase
          .from("nba_players")
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
      .from("nba_players")
      .select("id,player_name,team_name");

    if (existingPlayers) {
      const staleIds = existingPlayers
        .filter((p) => !currentPlayerKeys.has(`${p.player_name}|${p.team_name}`))
        .map((p) => p.id);

      if (staleIds.length > 0) {
        await supabase.from("nba_players").delete().in("id", staleIds);
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
