# Background Push Notifications — Setup

Makes reminders arrive **even when the app is closed**, like a real app
(meds, feeding sessions, vitals, Vitamin D, and date reminders).

## Your VAPID keys (already generated for you)

- **Public key** (already baked into `index.html`, safe to expose):
  `BP2dpWhhU-5ffvZWM0q-LAYuoqtknMvzeGmFyIzSJ7i-XyXWixxNumsLao3bjlT4FEHjtQhc_VMcACsJ2vjOnaI`
- **Private key** (KEEP SECRET — only goes into the Edge Function secret):
  `VI__p_j48AzmnC4pBqqc3FNTTUSH6LwFC2qRwd69CnY`

Also pick any random string as your **CRON_SECRET** (e.g. `care-push-9f3k2x`).

---

## Steps (do these once)

### 1. Database
Supabase → **SQL Editor** → paste `supabase/schema.sql` → **Run**
(adds the `push_subscriptions` table).

### 2. Deploy the Edge Function
Supabase → **Edge Functions** → **Deploy a new function** → name it exactly `push-tick`
→ paste the contents of `supabase/functions/push-tick/index.ts` → **Deploy**.
Then open the function's settings and **turn OFF "Verify JWT"** (so cron can call it;
it's protected by the CRON_SECRET instead).

### 3. Set the function secrets
Same function → **Secrets** → add:
| Name | Value |
|---|---|
| `VAPID_PUBLIC_KEY` | `BP2dpWhhU-5ffvZWM0q-LAYuoqtknMvzeGmFyIzSJ7i-XyXWixxNumsLao3bjlT4FEHjtQhc_VMcACsJ2vjOnaI` |
| `VAPID_PRIVATE_KEY` | `VI__p_j48AzmnC4pBqqc3FNTTUSH6LwFC2qRwd69CnY` |
| `VAPID_SUBJECT` | `mailto:youremail@example.com` |
| `CRON_SECRET` | your random string from above |

(`SUPABASE_URL` and `SUPABASE_SERVICE_ROLE_KEY` are provided automatically.)

### 4. Schedule it
Supabase → **SQL Editor** → open `supabase/push-cron.sql`, replace
`REPLACE_WITH_YOUR_CRON_SECRET` with your CRON_SECRET → **Run**.

### 5. Deploy the site
Push/upload the updated `index.html` and `sw.js`.

### 6. On each phone
Open the app → **Settings (⚙️) → enable notifications** → allow when asked.
- **iPhone:** first **Add to Home Screen** (Share → Add to Home Screen) and open it
  from that icon. Web Push on iOS only works for the installed app, not Safari tabs.

---

## Test it
- Temporarily add the current Qatar `HH:MM` to `MED_TIMES` in the function, redeploy,
  wait for the next minute → you should get a notification. Then revert.
- Or check runs: `select * from cron.job_run_details order by start_time desc limit 10;`
- The Edge Function logs (Dashboard → Edge Functions → push-tick → Logs) show
  `{cur, due, sent, removed}` each minute.

## How it works
`pg_cron` calls `push-tick` every minute → it computes which reminders match the
current Qatar minute (meds/feeding/vitals/VitD/dates) → sends a Web Push to every
row in `push_subscriptions`. Expired devices (404/410) are auto-removed.
