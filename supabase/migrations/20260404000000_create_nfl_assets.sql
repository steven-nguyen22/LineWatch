-- Team logos
CREATE TABLE nfl_teams (
    team_name TEXT PRIMARY KEY,
    espn_id INTEGER NOT NULL,
    logo_url TEXT NOT NULL
);

ALTER TABLE nfl_teams ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Allow public read" ON nfl_teams FOR SELECT USING (true);

-- QB headshots
CREATE TABLE nfl_qbs (
    id SERIAL PRIMARY KEY,
    player_name TEXT NOT NULL,
    espn_id INTEGER NOT NULL,
    headshot_url TEXT NOT NULL,
    team_name TEXT NOT NULL REFERENCES nfl_teams(team_name),
    UNIQUE(player_name, team_name)
);

CREATE INDEX idx_nfl_qbs_team ON nfl_qbs(team_name);

ALTER TABLE nfl_qbs ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Allow public read" ON nfl_qbs FOR SELECT USING (true);

-- RB headshots
CREATE TABLE nfl_rbs (
    id SERIAL PRIMARY KEY,
    player_name TEXT NOT NULL,
    espn_id INTEGER NOT NULL,
    headshot_url TEXT NOT NULL,
    team_name TEXT NOT NULL REFERENCES nfl_teams(team_name),
    UNIQUE(player_name, team_name)
);

CREATE INDEX idx_nfl_rbs_team ON nfl_rbs(team_name);

ALTER TABLE nfl_rbs ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Allow public read" ON nfl_rbs FOR SELECT USING (true);

-- Receiver headshots (WR or TE)
CREATE TABLE nfl_receivers (
    id SERIAL PRIMARY KEY,
    player_name TEXT NOT NULL,
    espn_id INTEGER NOT NULL,
    headshot_url TEXT NOT NULL,
    team_name TEXT NOT NULL REFERENCES nfl_teams(team_name),
    position TEXT NOT NULL CHECK (position IN ('WR', 'TE')),
    UNIQUE(player_name, team_name)
);

CREATE INDEX idx_nfl_receivers_team ON nfl_receivers(team_name);

ALTER TABLE nfl_receivers ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Allow public read" ON nfl_receivers FOR SELECT USING (true);
