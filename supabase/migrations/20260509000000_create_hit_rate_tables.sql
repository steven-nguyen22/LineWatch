-- =============================================================================
-- Hit Rate / Recent Trends — pilot tables (NBA only)
-- =============================================================================
-- Stores per-game prop and spread outcomes so the app can surface
-- "X of last N games" badges. Rows are inserted in two phases:
--   1. T-30 min before tip — `snapshot-lines-nba` edge fn writes the line
--      with actual_value/margin still NULL.
--   2. Daily 8am ET     — `fetch-nba-game-results` reads ESPN box scores
--      and UPDATEs the row with actual_value/margin and computes hit/covered.
-- AFTER INSERT triggers cap each (player, prop) and team to 15 rows so
-- storage stays flat and we never need to upgrade the Supabase free tier.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- player_game_results
-- -----------------------------------------------------------------------------
CREATE TABLE player_game_results (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    player_espn_id  INTEGER NOT NULL,
    player_name     TEXT NOT NULL,
    team_name       TEXT NOT NULL,
    sport_key       TEXT NOT NULL,
    game_id         TEXT NOT NULL,
    game_date       DATE NOT NULL,
    prop_type       TEXT NOT NULL,        -- e.g. 'player_points'
    line_value      NUMERIC NOT NULL,
    actual_value    NUMERIC,              -- NULL until post-game job runs
    hit             BOOLEAN,              -- NULL until post-game job runs
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),

    -- Each player has at most one row per (game, prop). Lets the post-game
    -- job UPDATE deterministically and prevents double-counting.
    UNIQUE (game_id, player_espn_id, prop_type)
);

-- Hot path: fetch a player's last 15 hits for a given prop type.
CREATE INDEX idx_player_results_lookup
    ON player_game_results (player_espn_id, prop_type, game_date DESC);

-- Sweep path: maintenance / cleanup queries by sport.
CREATE INDEX idx_player_results_sport_date
    ON player_game_results (sport_key, game_date);

ALTER TABLE player_game_results ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Allow public read" ON player_game_results FOR SELECT USING (true);


-- -----------------------------------------------------------------------------
-- team_game_results
-- -----------------------------------------------------------------------------
CREATE TABLE team_game_results (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    team_espn_id    INTEGER NOT NULL,
    team_name       TEXT NOT NULL,
    sport_key       TEXT NOT NULL,
    game_id         TEXT NOT NULL,
    game_date       DATE NOT NULL,
    -- Negative = favored. e.g. -3.5 means team needed to win by 4+ to cover.
    spread_line     NUMERIC NOT NULL,
    -- Final-score margin from THIS team's perspective (positive = won by N).
    actual_margin   NUMERIC,
    covered         BOOLEAN,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),

    UNIQUE (game_id, team_espn_id)
);

CREATE INDEX idx_team_results_lookup
    ON team_game_results (team_espn_id, game_date DESC);

CREATE INDEX idx_team_results_sport_date
    ON team_game_results (sport_key, game_date);

ALTER TABLE team_game_results ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Allow public read" ON team_game_results FOR SELECT USING (true);


-- -----------------------------------------------------------------------------
-- 15-game rolling-window triggers
-- -----------------------------------------------------------------------------
-- Standard "keep N most recent per partition" pattern. AFTER INSERT runs a
-- subquery that lists rows beyond OFFSET 15 for the same (player, prop) and
-- deletes them. Cheap because the index covers the lookup; the deletion
-- only fires on the (rare) 16th-and-beyond insert per partition.
CREATE OR REPLACE FUNCTION trim_player_game_results() RETURNS TRIGGER AS $$
BEGIN
    DELETE FROM player_game_results
    WHERE id IN (
        SELECT id
        FROM player_game_results
        WHERE player_espn_id = NEW.player_espn_id
          AND prop_type = NEW.prop_type
        ORDER BY game_date DESC
        OFFSET 15
    );
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trim_player_game_results_trigger
    AFTER INSERT ON player_game_results
    FOR EACH ROW
    EXECUTE FUNCTION trim_player_game_results();


CREATE OR REPLACE FUNCTION trim_team_game_results() RETURNS TRIGGER AS $$
BEGIN
    DELETE FROM team_game_results
    WHERE id IN (
        SELECT id
        FROM team_game_results
        WHERE team_espn_id = NEW.team_espn_id
        ORDER BY game_date DESC
        OFFSET 15
    );
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trim_team_game_results_trigger
    AFTER INSERT ON team_game_results
    FOR EACH ROW
    EXECUTE FUNCTION trim_team_game_results();
