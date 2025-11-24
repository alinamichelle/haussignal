#!/bin/bash
set -e

echo "🚀 Setting up HausSignal scraper droplet..."

# Step 1: Update and install dependencies
echo "📦 Installing system dependencies..."
apt update -y
apt install -y curl git build-essential libssl-dev libreadline-dev zlib1g-dev pkg-config wget unzip

# Step 2: Install Ruby (via RVM)
echo "💎 Installing Ruby 3.2.5..."
if ! command -v rvm >/dev/null 2>&1; then
  curl -sSL https://get.rvm.io | bash -s stable
fi
source /etc/profile.d/rvm.sh
if ! rvm list rubies | grep -q "ruby-3.2.5"; then
  rvm install ruby-3.2.5
fi
rvm use 3.2.5 --default

# Step 3: Install Node.js + Yarn
echo "📗 Installing Node.js..."
curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
apt install -y nodejs
npm install -g yarn

# Step 4: Install Playwright CLI + Chromium
echo "🎭 Installing Playwright..."
npm install -g playwright
playwright install --with-deps chromium

# Step 5: Clone repo (if not already)
echo "📂 Cloning HausSignal repo (if needed)..."
cd /root
if [ ! -d "haussignal" ]; then
  git clone https://github.com/alinamichelle/haussignal.git
fi
cd haussignal
git pull

# Step 6: Install app dependencies
echo "📚 Installing Ruby and Node dependencies..."
gem install bundler -v "~> 2.5" || true
bundle install
yarn install

echo "✅ Setup script finished."
echo ""
echo "Next steps:"
echo "1. Set environment variables (DATABASE_URL, LOFTY_LOGIN_EMAIL, etc.)"
echo "2. Run: RAILS_ENV=production bin/rails lofty:login"
echo "3. Run: SYNC_SLOT=X BATCH_SIZE=200 RAILS_ENV=production bin/rails lofty:sync_timelines"
