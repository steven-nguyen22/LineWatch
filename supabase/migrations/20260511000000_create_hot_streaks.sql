-- Top-3-per-sport hot-streak rankings, recomputed daily by the
-- compute-hot-streaks edge function (~13:30 UTC, after graders run).
-- Tiny table (≤3 rows × 4 in-season sports = 12 rows steady state),
-- replaced wholesale each day. Read directly by the iOS HotStreaksPage.
--
-- Streaks are mixed across categories — a single per-sport ranking
-- competes wins, spreads, and player props on raw streak count. There
-- is no minimum streak threshold; whatever happens to be the top 3 at
-- compute time gets shown.

CREATE TABLE hot_streaks (
    id              SERIAL PRIMARY KEY,
    sport_key       TEXT NOT NULL,           -- 'basketball_nba', etc.
    rank            INT  NOT NULL,           -- 1, 2, 3
    streak_count    INT  NOT NULL,           -- consecutive hits/covers/wins
    streak_type     TEXT NOT NULL,           -- 'wins' | 'spread' | <prop_type>
    -- Identity (exactly one of team_* or player_* populated):
    team_espn_id    INT,
    team_name       TEXT,
    player_espn_id  INT,
    player_name     TEXT,
    -- iOS-friendly display fields (precomputed so the client renders
    -- without lookup work):
    display_name    TEXT NOT NULL,           -- "Lakers" or "James Harden"
    description     TEXT NOT NULL,           -- "Wins" / "Spread" / "Points Over 25.5"
    last_game_date  DATE NOT NULL,           -- tiebreaker visibility
    computed_at     TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- One row per (sport, rank) — replaced wholesale each day.
CREATE UNIQUE INDEX idx_hot_streaks_sport_rank ON hot_streaks (sport_key, rank);

ALTER TABLE hot_streaks ENABLE ROW LEVEL SECURITY;

-- Public read (matches cached_odds / cached_player_props pattern).
-- No INSERT/UPDATE/DELETE policy — service-role-only writes (bypasses RLS).
CREATE POLICY "public read" ON hot_streaks FOR SELECT USING (true);
