-- Synthetic NFL fixture for off-season UI testing.
-- The Odds API returns no NFL events during the off-season, so we seed one
-- fake game (Chiefs @ Bills) with realistic shape. When NFL preseason starts,
-- the fetch-football-player-props Edge Function will overwrite/delete this row.
--
-- Delete with:
--   DELETE FROM cached_player_props WHERE event_id = 'nfl-fixture-001';
--   DELETE FROM cached_odds WHERE sport_key = 'americanfootball_nfl';

-- ============================================================================
-- cached_odds: one fake event, h2h/spreads/totals from 4 bookmakers
-- ============================================================================
INSERT INTO cached_odds (sport_key, data, updated_at) VALUES (
  'americanfootball_nfl',
  '[
    {
      "id": "nfl-fixture-001",
      "sport_key": "americanfootball_nfl",
      "sport_title": "NFL",
      "commence_time": "2026-09-14T20:25:00Z",
      "home_team": "Buffalo Bills",
      "away_team": "Kansas City Chiefs",
      "bookmakers": [
        {
          "key": "draftkings",
          "title": "DraftKings",
          "markets": [
            {"key": "h2h", "last_update": "2026-04-04T00:00:00Z", "outcomes": [
              {"name": "Buffalo Bills", "price": -135},
              {"name": "Kansas City Chiefs", "price": 115}
            ]},
            {"key": "spreads", "last_update": "2026-04-04T00:00:00Z", "outcomes": [
              {"name": "Buffalo Bills", "price": -110, "point": -2.5},
              {"name": "Kansas City Chiefs", "price": -110, "point": 2.5}
            ]},
            {"key": "totals", "last_update": "2026-04-04T00:00:00Z", "outcomes": [
              {"name": "Over", "price": -110, "point": 51.5},
              {"name": "Under", "price": -110, "point": 51.5}
            ]}
          ]
        },
        {
          "key": "fanduel",
          "title": "FanDuel",
          "markets": [
            {"key": "h2h", "last_update": "2026-04-04T00:00:00Z", "outcomes": [
              {"name": "Buffalo Bills", "price": -140},
              {"name": "Kansas City Chiefs", "price": 118}
            ]},
            {"key": "spreads", "last_update": "2026-04-04T00:00:00Z", "outcomes": [
              {"name": "Buffalo Bills", "price": -108, "point": -2.5},
              {"name": "Kansas City Chiefs", "price": -112, "point": 2.5}
            ]},
            {"key": "totals", "last_update": "2026-04-04T00:00:00Z", "outcomes": [
              {"name": "Over", "price": -112, "point": 51.5},
              {"name": "Under", "price": -108, "point": 51.5}
            ]}
          ]
        },
        {
          "key": "betmgm",
          "title": "BetMGM",
          "markets": [
            {"key": "h2h", "last_update": "2026-04-04T00:00:00Z", "outcomes": [
              {"name": "Buffalo Bills", "price": -130},
              {"name": "Kansas City Chiefs", "price": 110}
            ]},
            {"key": "spreads", "last_update": "2026-04-04T00:00:00Z", "outcomes": [
              {"name": "Buffalo Bills", "price": -115, "point": -2.5},
              {"name": "Kansas City Chiefs", "price": -105, "point": 2.5}
            ]},
            {"key": "totals", "last_update": "2026-04-04T00:00:00Z", "outcomes": [
              {"name": "Over", "price": -110, "point": 52.0},
              {"name": "Under", "price": -110, "point": 52.0}
            ]}
          ]
        },
        {
          "key": "caesars",
          "title": "Caesars",
          "markets": [
            {"key": "h2h", "last_update": "2026-04-04T00:00:00Z", "outcomes": [
              {"name": "Buffalo Bills", "price": -138},
              {"name": "Kansas City Chiefs", "price": 116}
            ]},
            {"key": "spreads", "last_update": "2026-04-04T00:00:00Z", "outcomes": [
              {"name": "Buffalo Bills", "price": -110, "point": -2.5},
              {"name": "Kansas City Chiefs", "price": -110, "point": 2.5}
            ]},
            {"key": "totals", "last_update": "2026-04-04T00:00:00Z", "outcomes": [
              {"name": "Over", "price": -105, "point": 51.5},
              {"name": "Under", "price": -115, "point": 51.5}
            ]}
          ]
        }
      ]
    }
  ]'::jsonb,
  now()
)
ON CONFLICT (sport_key) DO UPDATE
  SET data = EXCLUDED.data, updated_at = EXCLUDED.updated_at;

-- ============================================================================
-- cached_player_props: player_pass_yds / player_rush_yds / player_reception_yds
-- ============================================================================
INSERT INTO cached_player_props (event_id, sport_key, data, player_teams, updated_at) VALUES (
  'nfl-fixture-001',
  'americanfootball_nfl',
  '{
    "id": "nfl-fixture-001",
    "sport_key": "americanfootball_nfl",
    "sport_title": "NFL",
    "commence_time": "2026-09-14T20:25:00Z",
    "home_team": "Buffalo Bills",
    "away_team": "Kansas City Chiefs",
    "bookmakers": [
      {
        "key": "draftkings",
        "title": "DraftKings",
        "markets": [
          {"key": "player_pass_yds", "last_update": "2026-04-04T00:00:00Z", "outcomes": [
            {"name": "Over",  "description": "Patrick Mahomes", "price": -110, "point": 278.5},
            {"name": "Under", "description": "Patrick Mahomes", "price": -110, "point": 278.5},
            {"name": "Over",  "description": "Josh Allen",      "price": -115, "point": 265.5},
            {"name": "Under", "description": "Josh Allen",      "price": -105, "point": 265.5}
          ]},
          {"key": "player_rush_yds", "last_update": "2026-04-04T00:00:00Z", "outcomes": [
            {"name": "Over",  "description": "Isiah Pacheco",   "price": -110, "point": 62.5},
            {"name": "Under", "description": "Isiah Pacheco",   "price": -110, "point": 62.5},
            {"name": "Over",  "description": "James Cook",      "price": -115, "point": 71.5},
            {"name": "Under", "description": "James Cook",      "price": -105, "point": 71.5},
            {"name": "Over",  "description": "Ty Johnson",      "price": 105,  "point": 24.5},
            {"name": "Under", "description": "Ty Johnson",      "price": -125, "point": 24.5}
          ]},
          {"key": "player_reception_yds", "last_update": "2026-04-04T00:00:00Z", "outcomes": [
            {"name": "Over",  "description": "Travis Kelce",    "price": -115, "point": 58.5},
            {"name": "Under", "description": "Travis Kelce",    "price": -105, "point": 58.5},
            {"name": "Over",  "description": "Rashee Rice",     "price": -110, "point": 67.5},
            {"name": "Under", "description": "Rashee Rice",     "price": -110, "point": 67.5},
            {"name": "Over",  "description": "Xavier Worthy",   "price": -110, "point": 42.5},
            {"name": "Under", "description": "Xavier Worthy",   "price": -110, "point": 42.5},
            {"name": "Over",  "description": "Khalil Shakir",   "price": -115, "point": 51.5},
            {"name": "Under", "description": "Khalil Shakir",   "price": -105, "point": 51.5},
            {"name": "Over",  "description": "Keon Coleman",    "price": -110, "point": 38.5},
            {"name": "Under", "description": "Keon Coleman",    "price": -110, "point": 38.5},
            {"name": "Over",  "description": "Dalton Kincaid",  "price": -115, "point": 44.5},
            {"name": "Under", "description": "Dalton Kincaid",  "price": -105, "point": 44.5}
          ]}
        ]
      },
      {
        "key": "fanduel",
        "title": "FanDuel",
        "markets": [
          {"key": "player_pass_yds", "last_update": "2026-04-04T00:00:00Z", "outcomes": [
            {"name": "Over",  "description": "Patrick Mahomes", "price": -112, "point": 279.5},
            {"name": "Under", "description": "Patrick Mahomes", "price": -108, "point": 279.5},
            {"name": "Over",  "description": "Josh Allen",      "price": -110, "point": 264.5},
            {"name": "Under", "description": "Josh Allen",      "price": -110, "point": 264.5}
          ]},
          {"key": "player_rush_yds", "last_update": "2026-04-04T00:00:00Z", "outcomes": [
            {"name": "Over",  "description": "Isiah Pacheco",   "price": -115, "point": 63.5},
            {"name": "Under", "description": "Isiah Pacheco",   "price": -105, "point": 63.5},
            {"name": "Over",  "description": "James Cook",      "price": -110, "point": 72.5},
            {"name": "Under", "description": "James Cook",      "price": -110, "point": 72.5},
            {"name": "Over",  "description": "Ty Johnson",      "price": 110,  "point": 24.5},
            {"name": "Under", "description": "Ty Johnson",      "price": -130, "point": 24.5}
          ]},
          {"key": "player_reception_yds", "last_update": "2026-04-04T00:00:00Z", "outcomes": [
            {"name": "Over",  "description": "Travis Kelce",    "price": -110, "point": 59.5},
            {"name": "Under", "description": "Travis Kelce",    "price": -110, "point": 59.5},
            {"name": "Over",  "description": "Rashee Rice",     "price": -115, "point": 68.5},
            {"name": "Under", "description": "Rashee Rice",     "price": -105, "point": 68.5},
            {"name": "Over",  "description": "Xavier Worthy",   "price": -108, "point": 43.5},
            {"name": "Under", "description": "Xavier Worthy",   "price": -112, "point": 43.5},
            {"name": "Over",  "description": "Khalil Shakir",   "price": -110, "point": 52.5},
            {"name": "Under", "description": "Khalil Shakir",   "price": -110, "point": 52.5},
            {"name": "Over",  "description": "Keon Coleman",    "price": -115, "point": 39.5},
            {"name": "Under", "description": "Keon Coleman",    "price": -105, "point": 39.5},
            {"name": "Over",  "description": "Dalton Kincaid",  "price": -110, "point": 45.5},
            {"name": "Under", "description": "Dalton Kincaid",  "price": -110, "point": 45.5}
          ]}
        ]
      },
      {
        "key": "betmgm",
        "title": "BetMGM",
        "markets": [
          {"key": "player_pass_yds", "last_update": "2026-04-04T00:00:00Z", "outcomes": [
            {"name": "Over",  "description": "Patrick Mahomes", "price": -105, "point": 278.5},
            {"name": "Under", "description": "Patrick Mahomes", "price": -115, "point": 278.5},
            {"name": "Over",  "description": "Josh Allen",      "price": -110, "point": 266.5},
            {"name": "Under", "description": "Josh Allen",      "price": -110, "point": 266.5}
          ]},
          {"key": "player_rush_yds", "last_update": "2026-04-04T00:00:00Z", "outcomes": [
            {"name": "Over",  "description": "Isiah Pacheco",   "price": -110, "point": 62.5},
            {"name": "Under", "description": "Isiah Pacheco",   "price": -110, "point": 62.5},
            {"name": "Over",  "description": "James Cook",      "price": -120, "point": 71.5},
            {"name": "Under", "description": "James Cook",      "price": 100,  "point": 71.5}
          ]},
          {"key": "player_reception_yds", "last_update": "2026-04-04T00:00:00Z", "outcomes": [
            {"name": "Over",  "description": "Travis Kelce",    "price": -115, "point": 58.5},
            {"name": "Under", "description": "Travis Kelce",    "price": -105, "point": 58.5},
            {"name": "Over",  "description": "Rashee Rice",     "price": -110, "point": 67.5},
            {"name": "Under", "description": "Rashee Rice",     "price": -110, "point": 67.5},
            {"name": "Over",  "description": "Khalil Shakir",   "price": -110, "point": 51.5},
            {"name": "Under", "description": "Khalil Shakir",   "price": -110, "point": 51.5},
            {"name": "Over",  "description": "Dalton Kincaid",  "price": -110, "point": 44.5},
            {"name": "Under", "description": "Dalton Kincaid",  "price": -110, "point": 44.5}
          ]}
        ]
      },
      {
        "key": "caesars",
        "title": "Caesars",
        "markets": [
          {"key": "player_pass_yds", "last_update": "2026-04-04T00:00:00Z", "outcomes": [
            {"name": "Over",  "description": "Patrick Mahomes", "price": -108, "point": 279.5},
            {"name": "Under", "description": "Patrick Mahomes", "price": -112, "point": 279.5},
            {"name": "Over",  "description": "Josh Allen",      "price": -115, "point": 265.5},
            {"name": "Under", "description": "Josh Allen",      "price": -105, "point": 265.5}
          ]},
          {"key": "player_rush_yds", "last_update": "2026-04-04T00:00:00Z", "outcomes": [
            {"name": "Over",  "description": "Isiah Pacheco",   "price": -112, "point": 62.5},
            {"name": "Under", "description": "Isiah Pacheco",   "price": -108, "point": 62.5},
            {"name": "Over",  "description": "James Cook",      "price": -110, "point": 71.5},
            {"name": "Under", "description": "James Cook",      "price": -110, "point": 71.5},
            {"name": "Over",  "description": "Ty Johnson",      "price": 108,  "point": 24.5},
            {"name": "Under", "description": "Ty Johnson",      "price": -128, "point": 24.5}
          ]},
          {"key": "player_reception_yds", "last_update": "2026-04-04T00:00:00Z", "outcomes": [
            {"name": "Over",  "description": "Travis Kelce",    "price": -110, "point": 58.5},
            {"name": "Under", "description": "Travis Kelce",    "price": -110, "point": 58.5},
            {"name": "Over",  "description": "Rashee Rice",     "price": -112, "point": 67.5},
            {"name": "Under", "description": "Rashee Rice",     "price": -108, "point": 67.5},
            {"name": "Over",  "description": "Xavier Worthy",   "price": -110, "point": 42.5},
            {"name": "Under", "description": "Xavier Worthy",   "price": -110, "point": 42.5},
            {"name": "Over",  "description": "Khalil Shakir",   "price": -108, "point": 51.5},
            {"name": "Under", "description": "Khalil Shakir",   "price": -112, "point": 51.5},
            {"name": "Over",  "description": "Keon Coleman",    "price": -110, "point": 38.5},
            {"name": "Under", "description": "Keon Coleman",    "price": -110, "point": 38.5},
            {"name": "Over",  "description": "Dalton Kincaid",  "price": -110, "point": 44.5},
            {"name": "Under", "description": "Dalton Kincaid",  "price": -110, "point": 44.5}
          ]}
        ]
      }
    ]
  }'::jsonb,
  '{
    "Patrick Mahomes": "Kansas City Chiefs",
    "Isiah Pacheco":   "Kansas City Chiefs",
    "Travis Kelce":    "Kansas City Chiefs",
    "Rashee Rice":     "Kansas City Chiefs",
    "Xavier Worthy":   "Kansas City Chiefs",
    "Josh Allen":      "Buffalo Bills",
    "James Cook":      "Buffalo Bills",
    "Ty Johnson":      "Buffalo Bills",
    "Khalil Shakir":   "Buffalo Bills",
    "Keon Coleman":    "Buffalo Bills",
    "Dalton Kincaid":  "Buffalo Bills"
  }'::jsonb,
  now()
)
ON CONFLICT (event_id) DO UPDATE
  SET data = EXCLUDED.data,
      player_teams = EXCLUDED.player_teams,
      updated_at = EXCLUDED.updated_at;
