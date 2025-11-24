namespace :lofty do
  desc "Login to Lofty automatically and save storage state"
  task autologin: :environment do
    require 'playwright'

    Playwright.create(playwright_cli_executable_path: 'npx playwright') do |playwright|
      browser = playwright.chromium.launch(headless: true)
      context = browser.new_context
      page    = context.new_page

      puts "🔵 Opening Lofty login page..."
      page.goto("#{ENV['LOFTY_BASE_URL']}/login", waitUntil: 'networkidle')

      puts "🔑 Logging in with credentials..."
      page.fill('input[name="email"]', ENV['LOFTY_LOGIN_EMAIL'])
      page.fill('input[name="password"]', ENV['LOFTY_LOGIN_PASSWORD'])
      page.click('button[type="submit"]')

      puts "⏳ Waiting for login to complete..."
      page.wait_for_url(/crm\.lofty\.com/, timeout: 30000)
      sleep 5 # Let page fully load

      context.storage_state(path: "tmp/lofty_storage_state.json")
      puts "🟢 Saved Lofty session → tmp/lofty_storage_state.json"

      browser.close
    end
  end
end
