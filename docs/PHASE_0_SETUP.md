# 🎯 Phase 0 — Unsub Reporter (COMPLETE)

## ✅ What's Been Built

All 6 steps of Phase 0 are now complete:

### 1️⃣ Database Tables ✅
- **UUID-based tables** created with proper indexes
- `agents` - Realty Haus agents
- `leads` - Lofty leads with contact info
- `events` - Timeline events with JSONB metadata

**Run migrations:**
```bash
bin/rails db:migrate
```

### 2️⃣ Directory Structure ✅
```
app/services/lofty/
  ├── clients/     # For Phase 1 API clients
  ├── scrapers/    # Timeline scraper (Phase 0 complete)
  ├── parsers/     # Event parsers (Phase 1)
  └── sync/        # UnsubEventSyncService (Phase 0 complete)
```

### 3️⃣ Config Files ✅
- `config/lofty_selectors.yml` - CSS selectors for timeline scraping
- `config/lofty_timeline_types.yml` - Event type code mappings

### 4️⃣ Lofty Login ✅
**Rake task:** `bin/rails lofty:login`

This opens a browser, lets you log in manually, and saves the session for automated scraping.

### 5️⃣ Timeline Scraper ✅
**Service:** `Lofty::Scrapers::TimelineScraper`

- Auto-scrolls Lofty timeline to load all events
- Extracts event ID, type code, timestamp, content, audio URLs
- Filters for unsub events (type_code 113)
- Also has `scrape_all_for_lead` method ready for Phase 1

### 6️⃣ Unsub Sync Service ✅
**Service:** `Lofty::Sync::UnsubEventSyncService`

- Creates lead stubs if needed
- Parses unsub categories (seller reports, home reports, etc.)
- Saves to `events` table with deduplication
- Returns stats (new, updated, skipped)

---

## 🚀 How to Use (Phase 0 MVP)

### Step 1: Login to Lofty

```bash
bin/rails lofty:login
```

This opens a browser. Log in with:
- Email: `alina@realtyhaus.com`
- Password: (your password)

Wait 60 seconds for the session to save.

### Step 2: Test with One Lead

```bash
bin/rails haussignal:sync_unsub_one[YOUR_LOFTY_LEAD_ID]
```

Example:
```bash
bin/rails haussignal:sync_unsub_one[8446003473338351]
```

This will:
1. Scrape that lead's timeline
2. Find all unsub events
3. Save them to the database
4. Show you the results

### Step 3: Sync Multiple Leads

```bash
LEAD_IDS=123,456,789 bin/rails haussignal:sync_unsubs
```

Or if you already have leads in the database:
```bash
bin/rails haussignal:sync_unsubs
```

### Step 4: Generate Unsub Report

```bash
bin/rails unsub:report
```

This shows:
- **Total unsub count**
- **Breakdown by category** (seller reports, home reports, etc.)
- **Breakdown by agent**
- **Recent unsubs** (last 10)

---

## 📊 Example Output

```
============================================================
📊 UNSUB REPORT
============================================================

Total unsubs: 45

📋 By category:
  seller_reports       18
  home_reports         12
  market_alerts        8
  listing_alerts       5
  unknown              2

👥 By agent:
  Alina Villarreal     25
  Unassigned           20

🕒 Recent unsubs (last 10):
  2025-11-18 10:30 | John Smith                | seller_reports
  2025-11-17 15:45 | Jane Doe                  | home_reports
  ...

============================================================
```

---

## 🔍 Where to Find Lofty Lead IDs

1. Go to Lofty CRM
2. Open a lead's detail page
3. Look at the URL: `https://crm.lofty.com/admin/home/detail?leadId=XXXXXXX`
4. Copy the `leadId` parameter

---

## 🐛 Troubleshooting

### "Session state not found!"
**Solution:** Run `bin/rails lofty:login` first

### No unsubs found
**Possible causes:**
- Lead has no unsub events in timeline
- CSS selectors may have changed (check Lofty HTML)
- Session expired (re-run login task)

### Scraper times out
**Solution:** Increase wait times in `timeline_scraper.rb` or check your internet connection

---

## 🎯 What's Next?

Phase 0 is **COMPLETE**! You now have:
- ✅ Working unsub scraper
- ✅ Database storage
- ✅ Unsub reporting

### Ready for Phase 1?

Phase 1 will add:
1. **Full event scraping** (calls, emails, SMS, notes, etc.)
2. **Lofty API integration** for lead syncing
3. **Sidekiq background jobs** for automation
4. **Scheduled syncing** every 6 hours

---

## 📝 Notes

- Session state stored in: `tmp/lofty_storage_state.json` (gitignored)
- All credentials in: `.env` (gitignored)
- Models: `Agent`, `Lead`, `Event`
- Main services:
  - `Lofty::Scrapers::TimelineScraper`
  - `Lofty::Sync::UnsubEventSyncService`

**Have fun tracking those unsubs! 🎉**
