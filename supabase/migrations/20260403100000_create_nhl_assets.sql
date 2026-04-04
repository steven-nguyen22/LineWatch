-- Team logos
CREATE TABLE nhl_teams (
    team_name TEXT PRIMARY KEY,
    espn_id INTEGER NOT NULL,
    logo_url TEXT NOT NULL
);

ALTER TABLE nhl_teams ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Allow public read" ON nhl_teams FOR SELECT USING (true);

-- Player headshots
CREATE TABLE nhl_players (
    id SERIAL PRIMARY KEY,
    player_name TEXT NOT NULL,
    espn_id INTEGER NOT NULL,
    headshot_url TEXT NOT NULL,
    team_name TEXT NOT NULL REFERENCES nhl_teams(team_name),
    UNIQUE(player_name, team_name)
);

CREATE INDEX idx_nhl_players_team ON nhl_players(team_name);

ALTER TABLE nhl_players ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Allow public read" ON nhl_players FOR SELECT USING (true);
