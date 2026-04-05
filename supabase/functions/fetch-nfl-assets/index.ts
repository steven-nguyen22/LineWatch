import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

// ESPN team name → ESPN numeric team ID mapping
const NFL_TEAM_IDS: Record<string, number> = {
  "Arizona Cardinals": 22,
  "Atlanta Falcons": 1,
  "Baltimore Ravens": 33,
  "Buffalo Bills": 2,
  "Carolina Panthers": 29,
  "Chicago Bears": 3,
  "Cincinnati Bengals": 4,
  "Cleveland Browns": 5,
  "Dallas Cowboys": 6,
  "Denver Broncos": 7,
  "Detroit Lions": 8,
  "Green Bay Packers": 9,
  "Houston Texans": 34,
  "Indianapolis Colts": 11,
  "Jacksonville Jaguars": 30,
  "Kansas City Chiefs": 12,
  "Las Vegas Raiders": 13,
  "Los Angeles Chargers": 24,
  "Los Angeles Rams": 14,
  "Miami Dolphins": 15,
  "Minnesota Vikings": 16,
  "New England Patriots": 17,
  "New Orleans Saints": 18,
  "New York Giants": 19,
  "New York Jets": 20,
  "Philadelphia Eagles": 21,
  "Pittsburgh Steelers": 23,
  "San Francisco 49ers": 25,
  "Seattle Seahawks": 26,
  "Tampa Bay Buccaneers": 27,
  "Tennessee Titans": 10,
  "Washington Commanders": 28,
};

interface ESPNAthlete {
  id: string;
  displayName: string;
  headshot?: { href: string };
  position?: { abbreviation?: string };
}

interface PlayerRow {
  player_name: string;
  espn_id: number;
  headshot_url: string;
  team_name: string;
}

interface ReceiverRow extends PlayerRow {
  position: "WR" | "TE";
}

Deno.serve(async (_req) => {
  try {
    const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);

    // Step 1: Populate nfl_teams with all 32 teams
    const teamRows = Object.entries(NFL_TEAM_IDS).map(([name, espnId]) => ({
      team_name: name,
      espn_id: espnId,
      logo_url: `https://a.espncdn.com/i/teamlogos/nfl/500/${espnId}.png`,
    }));

    const { error: teamError } = await supabase
      .from("nfl_teams")
      .upsert(teamRows, { onConflict: "team_name" });

    if (teamError) {
      return new Response(
        JSON.stringify({ error: "Failed to upsert teams", detail: teamError.message }),
        { status: 500, headers: { "Content-Type": "application/json" } }
      );
    }

    // Step 2: Fetch rosters from ESPN for all 32 teams
    const qbRows: PlayerRow[] = [];
    const rbRows: PlayerRow[] = [];
    const receiverRows: ReceiverRow[] = [];
    let failedTeams = 0;

    for (const [teamName, espnId] of Object.entries(NFL_TEAM_IDS)) {
      try {
        const rosterUrl = `https://site.api.espn.com/apis/site/v2/sports/football/nfl/teams/${espnId}/roster`;
        const res = await fetch(rosterUrl);

        if (!res.ok) {
          failedTeams++;
          continue;
        }

        const data = await res.json();

        // ESPN NFL rosters: athletes[] groups (offense/defense/specialTeam) → items[] athletes
        if (Array.isArray(data.athletes)) {
          for (const group of data.athletes) {
            if (!Array.isArray(group.items)) continue;
            for (const athlete of group.items as ESPNAthlete[]) {
              if (!athlete.id || !athlete.displayName) continue;
              const pos = athlete.position?.abbreviation;
              if (pos !== "QB" && pos !== "RB" && pos !== "WR" && pos !== "TE") continue;

              const headshotUrl =
                athlete.headshot?.href ||
                `https://a.espncdn.com/i/headshots/nfl/players/full/${athlete.id}.png`;

              const base: PlayerRow = {
                player_name: athlete.displayName,
                espn_id: parseInt(athlete.id, 10),
                headshot_url: headshotUrl,
                team_name: teamName,
              };

              if (pos === "QB") qbRows.push(base);
              else if (pos === "RB") rbRows.push(base);
              else receiverRows.push({ ...base, position: pos });
            }
          }
        }

        // Rate limit courtesy — 200ms between ESPN requests
        await new Promise((resolve) => setTimeout(resolve, 200));
      } catch {
        failedTeams++;
      }
    }

    // Step 3: Upsert each player table in batches of 100
    async function upsertBatched<T extends { player_name: string; team_name: string }>(
      table: string,
      rows: T[],
    ): Promise<void> {
      for (let i = 0; i < rows.length; i += 100) {
        const batch = rows.slice(i, i + 100);
        const { error } = await supabase
          .from(table)
          .upsert(batch, { onConflict: "player_name,team_name" });
        if (error) console.error(`${table} upsert batch error: ${error.message}`);
      }
    }

    await upsertBatched("nfl_qbs", qbRows);
    await upsertBatched("nfl_rbs", rbRows);
    await upsertBatched("nfl_receivers", receiverRows);

    // Step 4: Clean up players no longer on any roster
    async function cleanupStale<T extends { player_name: string; team_name: string }>(
      table: string,
      freshRows: T[],
    ): Promise<void> {
      const freshKeys = new Set(freshRows.map((p) => `${p.player_name}|${p.team_name}`));
      const { data: existing } = await supabase
        .from(table)
        .select("id,player_name,team_name");
      if (!existing) return;
      const staleIds = existing
        .filter((p) => !freshKeys.has(`${p.player_name}|${p.team_name}`))
        .map((p) => p.id);
      if (staleIds.length > 0) {
        await supabase.from(table).delete().in("id", staleIds);
      }
    }

    await cleanupStale("nfl_qbs", qbRows);
    await cleanupStale("nfl_rbs", rbRows);
    await cleanupStale("nfl_receivers", receiverRows);

    return new Response(
      JSON.stringify({
        success: true,
        teams: teamRows.length,
        qbs: qbRows.length,
        rbs: rbRows.length,
        receivers: receiverRows.length,
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
