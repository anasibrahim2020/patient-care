# Patient Care — Netlify App

Static PWA for Netlify, with Supabase config loaded from Netlify environment variables
(the anon key is **never** hard-coded in the HTML — it is served by the Netlify Function
`/.netlify/functions/config`).

## Roles
- **admin** — full control: add/manage supplies, record everything, manage roles.
- **recorder** — records/fills all data (meds, feeding, vitals, notes, supply usage) but cannot add/delete stock items.
- **viewer** — read everything + print reports only.

Current mapping (in `supabase/schema.sql` → `app_roles`):
| Email | Role |
|---|---|
| admin@careportal.com | admin |
| jocel@careportal.com | recorder |
| ahmed@careportal.com | viewer |
| mervat@careportal.com | viewer |
| mohamed@careportal.com | viewer |
| eyad@careportal.com | viewer |
| radwa@careportal.com | viewer |
| yasmine@careportal.com | viewer |

The Supabase Project URL + publishable (anon) key are already baked into `index.html`
(they are public by design and protected by RLS). Netlify environment variables are
therefore **optional** — the app falls back to them only if the baked values are removed.

## Deploy steps

1. **Supabase → Authentication → Providers → Email**: disable "Confirm email".
   (Users already created: admin, jocel, ahmed, mervat, mohamed.)
2. **Supabase → SQL Editor**: paste `supabase/schema.sql` and Run — this creates the tables,
   sets roles (jocel = recorder), applies RLS, and **enables Realtime** (adds `app_state`,
   `action_log`, `vitals` to the `supabase_realtime` publication). Re-run any time you change roles
   or after this update to turn on live sync.
3. **Deploy the `patient-care-netlify` folder** (drag it onto Netlify, or connect a repo).
   ⚠️ Do NOT deploy the parent folder — it contains private patient documents (PDF, photos).

## Notes
- Not signed in → the app shows a full-screen login and no data.
- Security is enforced by Supabase RLS: viewers physically cannot write, even if the UI is bypassed.
- Opening `index.html` directly from disk (file://) runs in local single-user mode with full access (no login) for the owner.

## Live sync (real-time collaboration)
Every recorded action now shows **instantly on all signed-in devices** — no refresh needed:
- Med checkmarks, feeding-session steps, notes, supplies, and feed time sync through the
  `app_state` table (key/value, last-write-wins).
- Activity log + vitals sync through their own tables.
- A Supabase Realtime subscription re-renders each device the moment anything changes,
  and other users also get a toast/notification.

Requires the `schema.sql` above to have been run (it creates `app_state` and enables Realtime).
