CREATE TABLE fighter_headshots (
    fighter_name TEXT PRIMARY KEY,
    headshot_url TEXT,
    sport_key TEXT NOT NULL,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE fighter_headshots ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Allow public read" ON fighter_headshots FOR SELECT USING (true);
