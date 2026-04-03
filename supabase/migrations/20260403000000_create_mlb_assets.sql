-- Team logos
CREATE TABLE mlb_teams (
    team_name TEXT PRIMARY KEY,
    espn_id INTEGER NOT NULL,
    logo_url TEXT NOT NULL
);

ALTER TABLE mlb_teams ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Allow public read" ON mlb_teams FOR SELECT USING (true);

-- Player headshots
CREATE TABLE mlb_players (
    id SERIAL PRIMARY KEY,
    player_name TEXT NOT NULL,
    espn_id INTEGER NOT NULL,
    headshot_url TEXT NOT NULL,
    team_name TEXT NOT NULL REFERENCES mlb_teams(team_name),
    UNIQUE(player_name, team_name)
);

CREATE INDEX idx_mlb_players_team ON mlb_players(team_name);

ALTER TABLE mlb_players ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Allow public read" ON mlb_players FOR SELECT USING (true);
