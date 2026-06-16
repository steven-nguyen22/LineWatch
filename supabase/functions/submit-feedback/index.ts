// User feedback (bug reports / feature requests) submitted from the in-app
// feedback form. Emails the message to the LineWatch inbox via Resend.
//
// Auth: this is a CLIENT-invoked function (unlike the cron-driven fetch-*
// functions, which require service_role). `verify_jwt = true` in config.toml
// makes the gateway validate the JWT signature, and we additionally require the
// `authenticated` role here — so the public anon key alone cannot drive this
// function (a signed-in account is required). Combined with the per-user rate
// limit below, this contains inbox/quota spam.
//
// Resend sends from `onboarding@resend.dev` (no domain verification needed).
// Unverified Resend accounts may only deliver to the account owner's address,
// so the Resend account must be created with app.linewatch@gmail.com.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const RESEND_API_KEY = Deno.env.get("RESEND_API_KEY")!;
const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

const FEEDBACK_TO = "app.linewatch@gmail.com";
const FROM = "LineWatch Feedback <onboarding@resend.dev>";

const SUBJECT_MAX = 150;
const BODY_MAX = 5000;

// Per-user rate limits (rolling windows).
const MAX_PER_HOUR = 5;
const MAX_PER_DAY = 15;

interface FeedbackPayload {
  subject?: string;
  body?: string;
  userEmail?: string;
  appVersion?: string;
  platform?: string;
}

function json(payload: unknown, status: number): Response {
  return new Response(JSON.stringify(payload), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

// Decode the caller's JWT (already signature-verified by the gateway) and
// require a real signed-in user — blocks the public anon key. Returns the user
// id (`sub`) on success, or null if the token isn't an authenticated user.
function authenticatedUserId(req: Request): string | null {
  const auth = req.headers.get("authorization") ?? "";
  const token = auth.replace(/^Bearer\s+/i, "");
  try {
    const [, payloadB64] = token.split(".");
    const claims = JSON.parse(
      atob(payloadB64.replace(/-/g, "+").replace(/_/g, "/"))
    );
    if (claims.role !== "authenticated" || !claims.sub) return null;
    return claims.sub as string;
  } catch {
    return null;
  }
}

Deno.serve(async (req) => {
  if (req.method !== "POST") {
    return json({ error: "method not allowed" }, 405);
  }

  const userId = authenticatedUserId(req);
  if (!userId) {
    return json({ error: "authentication required" }, 401);
  }

  let payload: FeedbackPayload;
  try {
    payload = await req.json();
  } catch {
    return json({ error: "invalid JSON body" }, 400);
  }

  const subject = (payload.subject ?? "").trim();
  const body = (payload.body ?? "").trim();
  const userEmail = (payload.userEmail ?? "").trim();
  const appVersion = (payload.appVersion ?? "unknown").trim();
  const platform = (payload.platform ?? "unknown").trim();

  if (!subject || !body) {
    return json({ error: "subject and body are required" }, 400);
  }
  if (subject.length > SUBJECT_MAX || body.length > BODY_MAX) {
    return json({ error: "subject or body too long" }, 400);
  }

  const footer =
    `\n\n— — —\nFrom: ${userEmail || "unknown user"}` +
    `\nApp version: ${appVersion} · Platform: ${platform}`;

  const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);

  // Per-user rate limit: count this user's recent submissions and reject if
  // over the hourly or daily cap. Fetch the last day's rows once, then bucket.
  const dayAgo = new Date(Date.now() - 24 * 60 * 60 * 1000).toISOString();
  const hourAgo = new Date(Date.now() - 60 * 60 * 1000).toISOString();
  const { data: recent, error: countErr } = await supabase
    .from("feedback_submissions")
    .select("created_at")
    .eq("user_id", userId)
    .gte("created_at", dayAgo);

  if (countErr) {
    return json({ error: "rate check failed", detail: countErr.message }, 500);
  }
  const inDay = recent?.length ?? 0;
  const inHour = (recent ?? []).filter((r) => r.created_at >= hourAgo).length;
  if (inHour >= MAX_PER_HOUR || inDay >= MAX_PER_DAY) {
    return json(
      { error: "rate_limited", message: "You've sent a lot of feedback recently — please try again later." },
      429
    );
  }

  try {
    const res = await fetch("https://api.resend.com/emails", {
      method: "POST",
      headers: {
        Authorization: `Bearer ${RESEND_API_KEY}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        from: FROM,
        to: [FEEDBACK_TO],
        // Lets the developer reply straight to the user from their inbox.
        reply_to: userEmail || undefined,
        subject: `[LineWatch Feedback] ${subject}`,
        text: `${body}${footer}`,
      }),
    });

    if (!res.ok) {
      const detail = await res.text();
      return json({ error: "email send failed", status: res.status, detail }, 502);
    }

    // Record the successful submission for rate limiting (best-effort —
    // a logging failure shouldn't fail a feedback that already sent).
    await supabase.from("feedback_submissions").insert({ user_id: userId });

    return json({ success: true }, 200);
  } catch (err) {
    return json({ error: String(err) }, 500);
  }
});
