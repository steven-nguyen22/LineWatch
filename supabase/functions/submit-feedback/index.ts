// User feedback (bug reports / feature requests) submitted from the in-app
// feedback form. Emails the message to the LineWatch inbox via Resend.
//
// Auth: this is a CLIENT-invoked function (unlike the cron-driven fetch-*
// functions, which require service_role). `verify_jwt = true` in config.toml
// makes the Supabase gateway validate the caller's JWT before this runs, so
// only app users with a valid session (or the anon key) can reach it — a basic
// spam guard. We deliberately do NOT require the service_role claim here.
//
// Resend sends from `onboarding@resend.dev` (no domain verification needed).
// Unverified Resend accounts may only deliver to the account owner's address,
// so the Resend account must be created with app.linewatch@gmail.com.

const RESEND_API_KEY = Deno.env.get("RESEND_API_KEY")!;

const FEEDBACK_TO = "app.linewatch@gmail.com";
const FROM = "LineWatch Feedback <onboarding@resend.dev>";

const SUBJECT_MAX = 150;
const BODY_MAX = 5000;

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

Deno.serve(async (req) => {
  if (req.method !== "POST") {
    return json({ error: "method not allowed" }, 405);
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

    return json({ success: true }, 200);
  } catch (err) {
    return json({ error: String(err) }, 500);
  }
});
