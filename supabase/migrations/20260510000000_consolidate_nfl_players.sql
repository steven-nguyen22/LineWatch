-- Consolidate NFL player tables into a single `nfl_players` table.
--
-- Before: nfl_qbs, nfl_rbs, nfl_receivers — three separate tables, with
-- position implicit in the table name (and explicit only on receivers).
-- After:  nfl_players — single table matching the nhl_players / mlb_players
-- / nba_players pattern, with a `position` column carrying QB/RB/WR/TE.
--
-- Position is load-bearing: fetch-stats uses it to dispatch to position-
-- specific stat formatters (formatNFLPlayerStats reads QB vs RB vs WR/TE
-- stat lines differently). So the consolidated table needs a real column
-- for it; we can't just drop position and infer from elsewhere.
--
-- Data migration: existing rows from all three tables are copied into the
-- new table with the appropriate position before the old tables are
-- dropped. ON CONFLICT DO NOTHING guards against the unlikely case where
-- a player_name+team_name pair shows up in multiple source tables (e.g.
-- a player who switched positions mid-season).

-- Step 1: Create the unified table
CREATE TABLE nfl_players (
    id SERIAL PRIMARY KEY,
    player_name TEXT NOT NULL,
    espn_id INTEGER NOT NULL,
    headshot_url TEXT NOT NULL,
    team_name TEXT NOT NULL REFERENCES nfl_teams(team_name),
    position TEXT NOT NULL CHECK (position IN ('QB', 'RB', 'WR', 'TE')),
    UNIQUE(player_name, team_name)
);

CREATE INDEX idx_nfl_players_team ON nfl_players(team_name);

ALTER TABLE nfl_players ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Allow public read" ON nfl_players FOR SELECT USING (true);

-- Step 2: Migrate existing data — preserve all rows from the three legacy
-- tables. Position is derived from the source table for QBs and RBs;
-- receivers carry their own position column already.
INSERT INTO nfl_players (player_name, espn_id, headshot_url, team_name, position)
SELECT player_name, espn_id, headshot_url, team_name, 'QB'
FROM nfl_qbs
ON CONFLICT (player_name, team_name) DO NOTHING;

INSERT INTO nfl_players (player_name, espn_id, headshot_url, team_name, position)
SELECT player_name, espn_id, headshot_url, team_name, 'RB'
FROM nfl_rbs
ON CONFLICT (player_name, team_name) DO NOTHING;

INSERT INTO nfl_players (player_name, espn_id, headshot_url, team_name, position)
SELECT player_name, espn_id, headshot_url, team_name, position
FROM nfl_receivers
ON CONFLICT (player_name, team_name) DO NOTHING;

-- Step 3: Drop the legacy tables. CASCADE not needed — no FKs point
-- inward at these tables (verified: player_stats and player_game_results
-- key off player_name/espn_id, not foreign keys).
DROP TABLE nfl_qbs;
DROP TABLE nfl_rbs;
DROP TABLE nfl_receivers;
