CREATE TABLE cached_odds (
    sport_key TEXT PRIMARY KEY,
    data JSONB NOT NULL,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE cached_odds ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Allow public read" ON cached_odds FOR SELECT USING (true);
