-- Rate-limiting ledger for the in-app feedback form. One row per successful
-- submission; the submit-feedback edge function counts a user's recent rows to
-- enforce per-user limits. No message content is stored here (the message is
-- emailed, not persisted) — only enough to throttle abuse.
CREATE TABLE feedback_submissions (
    id BIGSERIAL PRIMARY KEY,
    user_id UUID NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_feedback_submissions_user_time
    ON feedback_submissions (user_id, created_at DESC);

-- RLS enabled with NO policies → no anon/authenticated client access at all.
-- Only the service_role (used by the edge function) bypasses RLS to read/write.
ALTER TABLE feedback_submissions ENABLE ROW LEVEL SECURITY;
