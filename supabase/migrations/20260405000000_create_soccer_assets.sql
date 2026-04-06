-- Soccer team logos and player headshots (UEFA Champions League)
CREATE TABLE soccer_teams (
    team_name TEXT PRIMARY KEY,
    espn_id INTEGER NOT NULL,
    logo_url TEXT NOT NULL
);

ALTER TABLE soccer_teams ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Allow public read" ON soccer_teams FOR SELECT USING (true);

CREATE TABLE soccer_players (
    id SERIAL PRIMARY KEY,
    player_name TEXT NOT NULL,
    espn_id INTEGER NOT NULL,
    headshot_url TEXT NOT NULL,
    team_name TEXT NOT NULL REFERENCES soccer_teams(team_name),
    UNIQUE(player_name, team_name)
);

CREATE INDEX idx_soccer_players_team ON soccer_players(team_name);

ALTER TABLE soccer_players ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Allow public read" ON soccer_players FOR SELECT USING (true);
