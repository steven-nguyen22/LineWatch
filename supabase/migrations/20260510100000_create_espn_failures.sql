-- Lightweight observability table for ESPN API failures.
--
-- Edge functions silently swallow non-2xx responses by design (a single
-- missed game isn't worth alerting on), but until now we had no trail of
-- those swallowed failures — meaning if ESPN ever started rate-limiting
-- us, we wouldn't notice until graded data dried up.
--
-- The new `espnFetch()` helper (added to all snapshot + grader functions)
-- INSERTs a row here for every non-2xx HTTP response and every network
-- error. A quick:
--   SELECT function_name, status, COUNT(*) FROM espn_failures
--    WHERE occurred_at > NOW() - INTERVAL '24 hours'
--    GROUP BY 1, 2 ORDER BY 3 DESC;
-- now shows whether anything's wrong at a glance.
--
-- Self-pruning via AFTER INSERT trigger keeps the table at <7 days.
-- Failures should be rare in steady state so this is essentially free.

CREATE TABLE espn_failures (
    id            SERIAL PRIMARY KEY,
    function_name TEXT NOT NULL,
    url           TEXT NOT NULL,
    status        INT,        -- HTTP status; NULL on network error
    error         TEXT,       -- network-error message; NULL on HTTP non-2xx
    occurred_at   TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_espn_failures_recent ON espn_failures (occurred_at DESC);

CREATE OR REPLACE FUNCTION prune_espn_failures() RETURNS TRIGGER AS $$
BEGIN
    DELETE FROM espn_failures WHERE occurred_at < NOW() - INTERVAL '7 days';
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_prune_espn_failures
AFTER INSERT ON espn_failures
EXECUTE FUNCTION prune_espn_failures();

-- Service-role-only access (RLS bypassed for service role; no public policy).
ALTER TABLE espn_failures ENABLE ROW LEVEL SECURITY;
