# Putting wya?! on real servers

Everything here is ready for when the app is done. Nothing in it has been run on a real account yet: the database was
checked on a plain Postgres with Supabase's sign-in faked, and the two Workers against fakes.

| File | What it is |
|---|---|
| `schema.sql` | The whole database for Supabase: people, stamps, lists, posts, comments, chats, reports, Solo and Teams, notifications, with who may read and change what. |
| `ai-worker.js`, `wrangler-ai.toml` | The AI: a Cloudflare Worker that holds the Anthropic key, checks who is asking, and keeps a daily limit per person (more for premium). |
| `data-worker.js`, `wrangler-data.toml` | The travel data: a Cloudflare Worker that serves the files the Mac's data server builds, from an R2 bucket. |
| `upload-data.sh` | Copies `server/public.nosync/v1` into that bucket. |
| `test-workers.mjs` | `node test-workers.mjs` checks both Workers without keys or network. |

## In order

1. **Apple Developer Program** ($99 a year). Sign in with Apple, push and payments all need it.
2. **Supabase**: a new project, region **Zurich**. SQL editor, paste `schema.sql`, Run.
   Authentication, Providers: turn on Apple, Google and Email.
3. **Cloudflare**: an account, then in Terminal from the wya?! folder:
   - `npx wrangler login`
   - The data: `npx wrangler r2 bucket create wya-data`, then `sh server/launch/upload-data.sh`,
     then `npx wrangler deploy -c server/launch/wrangler-data.toml`.
     In `src/api.js`, `API_BASE` becomes the Worker's address plus `/v1/`.
   - The AI: `npx wrangler kv namespace create LIMITS` (paste its id into `wrangler-ai.toml`),
     fill `SUPABASE_URL` and the two model ids in that file, then
     `npx wrangler secret put ANTHROPIC_API_KEY -c server/launch/wrangler-ai.toml` (paste the key
     from `server/secret.nosync/anthropic-key.txt`; it never goes in the app),
     `npx wrangler secret put SUPABASE_ANON_KEY -c server/launch/wrangler-ai.toml`, and
     `npx wrangler deploy -c server/launch/wrangler-ai.toml`.
4. The app then signs in with Supabase and sends its questions to the AI Worker with the
   person's token. That wiring in the app is the next piece of work, once these exist.

## What the database promises

- Row Level Security is on for every table: you change only your own things; lists follow
  their "who can see it"; chats are read only by their members; reports are seen only by the
  one who made them.
- Your handle changes at most twice in any 14 days, checked by the database itself.
- Premium can only be set by the server (the purchase webhook), never by the app.
- Solo: where you are is stored rounded to about 5 km and forgotten after a day; nobody can read
  it. `solo_near()` answers who is within your distance, rounded to 5 km, and only for someone
  verified and over 18. When two people both connect, the database opens their chat and tells
  both.
- No ID document and no selfie is ever stored here: only "verified, over 18, on this date".
