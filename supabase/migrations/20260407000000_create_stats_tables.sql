-- Team stats (W-L, home/road, L10, etc.) from ESPN
CREATE TABLE team_stats (
    team_name TEXT NOT NULL,
    sport_key TEXT NOT NULL,
    stats JSONB NOT NULL DEFAULT '{}',
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (team_name, sport_key)
);

ALTER TABLE team_stats ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Allow public read" ON team_stats FOR SELECT USING (true);

-- Player season averages from ESPN
CREATE TABLE player_stats (
    player_name TEXT NOT NULL,
    team_name TEXT NOT NULL,
    sport_key TEXT NOT NULL,
    stats JSONB NOT NULL DEFAULT '{}',
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (player_name, team_name, sport_key)
);

CREATE INDEX idx_player_stats_sport ON player_stats(sport_key);
ALTER TABLE player_stats ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Allow public read" ON player_stats FOR SELECT USING (true);
