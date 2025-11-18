# 📘 HausSignal — Lofty → Rails/Postgres Event Mirror

**Internal "black box recorder" for Lofty CRM data: leads, events, and unsubs**

## 🎯 Purpose

HausSignal mirrors Lofty CRM data into your own PostgreSQL database, giving you:
- Full control over your lead and event data
- Unsub reporting and analytics
- Foundation for coaching, transcription, and future integrations
- No vendor lock-in

## 📦 Stack

- **Ruby 3.2.5** + **Rails 7.1**
- **PostgreSQL** for data storage
- **Playwright** (Ruby client) for Lofty timeline scraping
- **Sidekiq** + **Sidekiq-Cron** for background jobs
- **Redis** for Sidekiq queue

## 🚀 Quick Start

### Prerequisites

- Ruby 3.2.5 (via rbenv/rvm)
- Rails 7.1+
- PostgreSQL running
- Node.js 18+ (for Playwright)
- Redis (for Sidekiq)

### Setup

```bash
# Clone the repo
git clone git@github.com:alinamichelle/haussignal.git
cd haussignal

# Install dependencies
bundle install

# Install Playwright browsers
npx playwright install chromium

# Create databases
bin/rails db:create
bin/rails db:migrate

# Set up environment variables
cp .env.example .env
# Edit .env with your configuration
```

### Environment Variables

Create a `.env` file:

```bash
DATABASE_URL=postgresql://localhost:5432/haussignal_development
LOFTY_BASE_URL=https://crm.lofty.com
LOFTY_API_KEY=your_api_key_here
ORG_ID=realty-haus
```

## 📋 Development Phases

### Phase 0 — Week 1 MVP: Unsub Reporter ✅

**Goal:** CLI unsub report showing:
- Total unsub count
- Breakdown by category (seller reports, home reports, etc.)
- Breakdown by agent

### Phase 1 — Full Event Mirror

**Goal:** Mirror all Lofty events:
- Calls (with audio)
- Emails
- SMS
- Smart plan steps
- Notes
- Lead updates

## 🗄️ Database Schema

### Core Models

- **Agent** - Realty Haus agents
- **Lead** - Lofty leads with contact info and status
- **Event** - All timeline events (calls, emails, unsubs, etc.)

## 📚 Documentation

See `/docs` folder for:
- Timeline mapping
- Lofty selectors
- Event type codes

## 🔐 Security

- Never commit `.env` file
- Use environment variables for all credentials
- GitHub repository is private

## 📊 Project Status

**Current Phase:** Initial setup complete

**Next Steps:**
1. Create database migrations (Agent, Lead, Event)
2. Map Lofty timeline HTML structure
3. Build Playwright login task
4. Create unsub scraper
5. Generate first unsub report

---

**Repository:** https://github.com/alinamichelle/haussignal  
**Organization:** Realty Haus
