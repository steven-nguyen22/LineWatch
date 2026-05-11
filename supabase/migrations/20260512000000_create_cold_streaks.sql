-- Top-3-per-sport COLD-streak rankings — the parallel of hot_streaks.
-- Computed by the same compute-hot-streaks edge function (which now
-- writes both tables). See migration 20260511 for the hot version;
-- this table has identical shape.
--
-- The streak_count column still means "consecutive matches at the head
-- of the newest-first row list" — just with the cold predicate
-- (consecutive losses / non-covers / props missed) instead of the hot
-- predicate (wins / covers / hits).

CREATE TABLE cold_streaks (
    id              SERIAL PRIMARY KEY,
    sport_key       TEXT NOT NULL,
    rank            INT  NOT NULL,
    streak_count    INT  NOT NULL,           -- consecutive losses/non-covers/misses
    streak_type     TEXT NOT NULL,           -- 'wins' | 'spread' | <prop_type>
    -- Identity (exactly one of team_* or player_* populated):
    team_espn_id    INT,
    team_name       TEXT,
    player_espn_id  INT,
    player_name     TEXT,
    -- iOS-friendly display fields (precomputed):
    display_name    TEXT NOT NULL,
    description     TEXT NOT NULL,
    last_game_date  DATE NOT NULL,
    computed_at     TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- One row per (sport, rank) — replaced wholesale each day.
CREATE UNIQUE INDEX idx_cold_streaks_sport_rank ON cold_streaks (sport_key, rank);

ALTER TABLE cold_streaks ENABLE ROW LEVEL SECURITY;

-- Public read (matches hot_streaks / cached_odds pattern).
CREATE POLICY "public read" ON cold_streaks FOR SELECT USING (true);
