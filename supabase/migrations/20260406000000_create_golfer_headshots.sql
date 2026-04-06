CREATE TABLE golfer_headshots (
    golfer_name TEXT PRIMARY KEY,
    headshot_url TEXT,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE golfer_headshots ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Allow public read" ON golfer_headshots FOR SELECT USING (true);
