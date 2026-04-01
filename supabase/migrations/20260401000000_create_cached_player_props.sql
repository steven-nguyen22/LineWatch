-- Cached player props table (one row per event)
CREATE TABLE cached_player_props (
    event_id TEXT PRIMARY KEY,
    sport_key TEXT NOT NULL,
    data JSONB NOT NULL,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Index for filtering by sport
CREATE INDEX idx_player_props_sport ON cached_player_props(sport_key);

-- Enable RLS with public read
ALTER TABLE cached_player_props ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Allow public read" ON cached_player_props FOR SELECT USING (true);
