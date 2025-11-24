# Haussignal Lofty Sync – Multi-Worker Setup

## Goal
Sync all ~4,237 leads in Railway with Lofty timelines, using multiple workers, without overlapping or breaking stuff.

---

## 📌 REQUIREMENTS BEFORE STARTING

- **Mac fully charged or plugged in**
- **Close RAM-hog apps:**
  - Chrome tabs you don't need
  - Notion
  - Figma
  - Slack windows
  - VS Code windows you don't need
- **Run from the haussignal directory:** `cd ~/Projects/haussignal`

---

## ✅ Preconditions (Already Completed)

1. **DATABASE_URL is configured in `.env` file** (points to Railway Postgres)

2. **Verify connection:**
   ```bash
   cd ~/Projects/haussignal
   bin/rails runner "puts 'Total leads: ' + Lead.count.to_s"
   # Expected: Total leads: 4237
   ```

3. **`sync_slot` column exists and is populated (0–3 per lead):**
   - Migration `AddSyncSlotToLeads` has been run
   - All leads have been assigned slots 0-3 using CRC32 hash

4. **`timeline_synced_at` is NULL for all leads:**
   - All 4,237 leads are marked as unsynced and ready to scrape

---

## 🚀 STARTING 2-WORKER SCRAPE (SAFE DEFAULT)

Each worker processes only leads in its assigned slot. Workers do **not** overlap.

### Worker 0 (Slot 0) – 1,149 leads
```bash
cd ~/Projects/haussignal
RAILS_ENV=development SYNC_SLOT=0 BATCH_SIZE=200 bin/rails lofty:sync_timelines
```

### Worker 1 (Slot 1) – 1,042 leads
**Open a NEW terminal window:**
```bash
cd ~/Projects/haussignal
RAILS_ENV=development SYNC_SLOT=1 BATCH_SIZE=200 bin/rails lofty:sync_timelines
```

---

## 🚀 OPTIONAL: 3-WORKER SCRAPE (IF YOUR MAC HAS 32GB RAM)

### Worker 2 (Slot 2) – 1,015 leads
**Only run if your laptop is stable with 2 workers:**
```bash
cd ~/Projects/haussignal
SYNC_SLOT=2 BATCH_SIZE=200 bin/rails lofty:sync_timelines
```

---

## 📊 Progress Checking Commands

### Total leads in Railway DB
```bash
cd ~/Projects/haussignal
bin/rails runner "puts 'Total leads: ' + Lead.count.to_s"
```

### Remaining unsynced leads (all slots)
```bash
bin/rails runner "puts 'Unsynced leads: ' + Lead.where(timeline_synced_at: nil).count.to_s"
```

### Per-slot progress breakdown
```bash
bin/rails runner "
(0..3).each do |s|
  total  = Lead.where(sync_slot: s).count
  left   = Lead.where(sync_slot: s, timeline_synced_at: nil).count
  puts \"Slot #{s}: #{left} / #{total} remaining\"
end
"
```

**Example output:**
```
Slot 0: 1149 / 1149 remaining
Slot 1: 1042 / 1042 remaining
Slot 2: 1015 / 1015 remaining
Slot 3: 1031 / 1031 remaining
```

---

## ⏸️ Stopping & Restarting Workers

### To stop a worker:
Press `Ctrl + C` in the terminal running that worker.

### To restart:
Just rerun the same command:
```bash
SYNC_SLOT=0 BATCH_SIZE=200 bin/rails lofty:sync_timelines
```

**Note:** Already-synced leads are automatically skipped because they have `timeline_synced_at` set.

---

## 🎯 Task Behavior

The `lofty:sync_timelines` task:
- Reads `BATCH_SIZE` (default 200 leads per batch)
- If `SYNC_SLOT` is set, only processes leads with that slot
- Only processes leads with `timeline_synced_at: nil`
- Marks leads as synced by setting `timeline_synced_at` after successful scrape

---

## 🔧 Environment Variables Summary

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `DATABASE_URL` | Yes | - | Railway Postgres connection string |
| `SYNC_SLOT` | Optional | - | Worker slot (0-3). If not set, processes all slots |
| `BATCH_SIZE` | Optional | 200 | Number of leads per batch |
| `FULL` | Optional | false | Set to `true` to force full sync (ignore `timeline_synced_at`) |

---

## 📋 Slot Distribution

| Slot | Lead Count |
|------|------------|
| 0    | 1,149      |
| 1    | 1,042      |
| 2    | 1,015      |
| 3    | 1,031      |
| **Total** | **4,237** |

---

## 🛑 WHAT NOT TO DO

❌ **Do NOT launch more than 1 worker per slot**  
❌ **Do NOT run workers without setting SYNC_SLOT**  
❌ **Do NOT reboot mid-browser-window** (stop the process first with Ctrl+C)  
❌ **Do NOT attempt 10 workers** — you will fry your RAM  

---

## ⚠️ Important Notes

1. **Start with 2 workers** (slots 0 and 1) to avoid memory issues
2. Each worker needs its own terminal window/tab
3. Workers can be stopped and restarted independently
4. All writes go directly to Railway Postgres (no local DB involved)
5. Scraper runs on laptop using Playwright + manual Lofty login
6. Already-synced leads are automatically skipped on restart

---

## 🎉 You're Ready

You now have:

✔ Database in the cloud (Railway)  
✔ Lead distribution across 4 slots  
✔ Workers isolated per slot  
✔ Timeline sync fully reset  
✔ Ready to scrape 4k+ leads safely and MUCH faster
