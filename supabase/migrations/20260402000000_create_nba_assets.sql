-- Team logos
CREATE TABLE nba_teams (
    team_name TEXT PRIMARY KEY,
    espn_id INTEGER NOT NULL,
    logo_url TEXT NOT NULL
);

ALTER TABLE nba_teams ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Allow public read" ON nba_teams FOR SELECT USING (true);

-- Player headshots
CREATE TABLE nba_players (
    id SERIAL PRIMARY KEY,
    player_name TEXT NOT NULL,
    espn_id INTEGER NOT NULL,
    headshot_url TEXT NOT NULL,
    team_name TEXT NOT NULL REFERENCES nba_teams(team_name),
    UNIQUE(player_name, team_name)
);

CREATE INDEX idx_nba_players_team ON nba_players(team_name);

ALTER TABLE nba_players ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Allow public read" ON nba_players FOR SELECT USING (true);
