ALTER TABLE cached_player_props
ADD COLUMN player_teams JSONB DEFAULT '{}';
