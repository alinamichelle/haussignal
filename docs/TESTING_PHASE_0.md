# 🧪 Phase 0 Testing Guide

## 1️⃣ First Real-World Test: Validate Unsub Logic

### Step 1: Login to Lofty

```bash
bin/rails lofty:login
```

- Browser opens automatically
- Log in with: `alina@realtyhaus.com`
- Wait 60 seconds for session to save
- You'll see: `🟢 Saved Lofty session → tmp/lofty_storage_state.json`

### Step 2: Find a Test Lead ID

1. Go to Lofty CRM in your browser
2. Open a lead that you know has unsub events
3. Copy the `leadId` from URL: `https://crm.lofty.com/admin/home/detail?leadId=XXXXXXX`

Example lead ID: `1142886436094613`

### Step 3: Test Raw Timeline Scraping

```bash
bin/rails haussignal:scrape_timeline_one_lead[1142886436094613]
```

**What to look for:**
- Total timeline entries found
- Breakdown by type code
- Unsub events (type 113) listed
- No errors or crashes

**Example output:**
```
🔍 Scraping timeline for lead: 1142886436094613

📊 Found 156 total timeline entries

📋 By type code:
  105   → 45 events
  113   → 3 events
  103   → 89 events
  ...

🚫 Unsub events found: 3
  - Yesterday at 3:45 PM: unsubscribed from seller reports
  - Nov 15 at 10:30 AM: unsubscribed from home reports
```

### Step 4: Sync Unsub Events

```bash
bin/rails haussignal:sync_unsub_one[1142886436094613]
```

**What to look for:**
- Events created successfully
- Subject lines extracted from preceding emails
- Category detection working
- Warning logs for any missing data

**Example output:**
```
🔄 Syncing unsub events for lead: 1142886436094613
📊 Found 156 total events, 3 unsubs
  ✅ Created unsub: abc123 - seller_reports - Subject: Your Weekly Market Report
  ✅ Created unsub: def456 - home_reports - Subject: New Listings Just For You
⚠️  No preceding email found for unsub timeline_id=xyz789 lead=1142886436094613
📊 Sync complete: 2 new, 0 updated, 1 skipped
⚠️  Missing data: 1 no email match, 0 no subject
```

### Step 5: Verify in Rails Console

```bash
bin/rails c
```

In console:
```ruby
# Find the lead
lead = Lead.find_by(lofty_lead_id: "1142886436094613")

# Get all unsub events for this lead
unsubs = lead.events.where(event_type: :unsub)

# Check each unsub event
unsubs.each do |e|
  puts "----"
  puts "Occurred at: #{e.occurred_at}"
  puts "Raw: #{e.raw_text}"
  puts "Category: #{e.metadata['unsub_category']}"
  puts "From subject: #{e.metadata['unsubbedFromSubject']}"
  puts "From sent at: #{e.metadata['unsubbedFromSentAt']}"
  puts "From type: #{e.metadata['unsubbedFromType']}"
end
```

**What to verify:**
- ✅ Subject matches what you see in Lofty under the previous email
- ✅ Unsub category looks correct (seller_reports, home_reports, etc.)
- ✅ Timestamps make sense (email sent before unsub)
- ✅ Raw text contains the unsub message you see in Lofty

### Step 6: Test with 3-5 More Leads

Repeat steps 3-5 with different leads to validate consistency.

---

## 2️⃣ Batch Test: Small Controlled Run

### Sync Multiple Leads

```bash
# Method 1: Specify lead IDs
LEAD_IDS=1142886436094613,8446003473338351,9876543210123 bin/rails haussignal:sync_unsubs

# Method 2: If you already have leads in DB
bin/rails haussignal:sync_unsubs
```

### Run the Report

```bash
bin/rails unsub:report
```

**Expected output:**
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

📨 Top offending subjects (campaigns with most unsubs):
  [5x] Your Weekly Seller Report - Market Update
  [4x] New Listings Alert - Properties in Your Area
  [3x] Home Valuation Update for 123 Main St
  ...

👥 By agent:
  Alina Villarreal     25
  Unassigned           20

⚠️  Data Quality:
  Missing subjects: 3 (6.7%)
  Missing email match: 2 (4.4%)

🕒 Recent unsubs (last 10):
  2025-11-18 10:30 | John Smith            | Your Weekly Seller Report
  2025-11-17 15:45 | Jane Doe              | New Listings Alert
  ...

============================================================
```

### Sanity Checks

✅ **Total unsubs looks plausible**
- Compare with your Lofty reports
- Should be in the right ballpark

✅ **Top subjects look like actual campaigns**
- Not a bunch of "unknown" or nil
- Recognizable email campaigns

✅ **Categories make sense**
- Not all showing as "unknown"
- seller_reports, home_reports, etc. are identified

❌ **Red flags:**
- High % of missing subjects → Need to refine email parsing
- High % of missing email match → Timeline ordering issue
- All categories show as "unknown" → Category detection broken

---

## 3️⃣ Debugging Common Issues

### Issue: "Session state not found!"

**Cause:** Haven't run login task or session expired

**Fix:**
```bash
bin/rails lofty:login
```

### Issue: No unsubs found for a lead

**Possible causes:**
1. Lead genuinely has no unsub events
2. CSS selectors changed (check Lofty HTML)
3. Timeline didn't load fully (increase scroll wait time)

**Debug:**
```bash
# Check raw scraping
bin/rails haussignal:scrape_timeline_one_lead[LEAD_ID]
```

### Issue: Missing subjects (high %)

**Cause:** Email subject extraction regex needs tuning

**Fix:** Open `app/services/lofty/sync/unsub_event_sync_service.rb` and adjust `extract_subject` method.

**Debug in console:**
```ruby
# Get a raw email entry
lead = Lead.find_by(lofty_lead_id: "...")
scraper = Lofty::Scrapers::TimelineScraper.new
entries = scraper.scrape_all_for_lead(lead.lofty_lead_id)
email = entries.find { |e| [103, 105].include?(e.type_code) }

# Test subject extraction
puts email.raw_text
# Manually check what the subject should be
```

### Issue: Missing email match (high %)

**Cause:** Timeline entries might not be in chronological order, or email type codes are wrong

**Fix:** Check `find_preceding_email` logic in sync service

**Debug:**
```ruby
# In console, check event order
entries = scraper.scrape_all_for_lead("LEAD_ID")
entries.first(20).each do |e|
  puts "#{e.type_code.to_s.ljust(5)} | #{e.timestamp_text} | #{e.raw_text[0..50]}"
end
```

---

## 4️⃣ Data Quality Monitoring

### Check Stats After Each Sync

The sync service now logs:
```
⚠️  Missing data: X no email match, Y no subject
```

**Good benchmarks:**
- Missing email match: <10%
- Missing subjects: <15%

**If higher:** Time to refine the parsing logic!

### Rails Console Queries

```ruby
# Total unsubs
Event.where(event_type: :unsub).count

# Missing subjects
Event.where(event_type: :unsub).where("metadata->>'unsubbedFromSubject' IS NULL").count

# Missing email match
Event.where(event_type: :unsub).where("metadata->>'unsubbedFromType' IS NULL").count

# Top subjects
Event.where(event_type: :unsub)
     .pluck("metadata->>'unsubbedFromSubject'")
     .compact
     .tally
     .sort_by { |k,v| -v }
     .first(10)
```

---

## 5️⃣ When You're Happy → Move to Phase 1

Once you can:
- ✅ Successfully scrape 10+ leads
- ✅ See sensible unsub reports
- ✅ Verify subjects match Lofty emails
- ✅ Data quality >85% (missing subjects <15%)

**You're ready for Phase 1!** 🚀

Phase 1 Sprint 1 is already scaffolded:
```bash
# Will sync leads from Lofty API (once configured)
bin/rails haussignal:lead_sync
```

---

## 📝 Testing Checklist

Before moving to Phase 1:

- [ ] Login task works
- [ ] Can scrape 1 lead successfully
- [ ] Can sync unsubs for 1 lead
- [ ] Console verification shows correct data
- [ ] Batch sync works on 5+ leads
- [ ] Report shows meaningful data
- [ ] Top subjects are recognizable
- [ ] Categories are mostly correct
- [ ] Data quality >85%
- [ ] No major errors or crashes

**Good luck! 🎉**
