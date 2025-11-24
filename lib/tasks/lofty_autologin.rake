namespace :lofty do
  desc "Login to Lofty automatically and save storage state"
  task autologin: :environment do
    require 'playwright'

    Playwright.create(playwright_cli_executable_path: 'npx playwright') do |playwright|
      browser = playwright.chromium.launch(headless: true)
      context = browser.new_context
      page    = context.new_page

      puts "🔵 Opening Lofty CRM..."
      page.goto(ENV['LOFTY_BASE_URL'], waitUntil: 'networkidle')
      sleep 3

      puts "🔑 Logging in with credentials..."
      # Try multiple possible selectors for email/username field
      email_selector = page.locator('input[type="email"], input[name="email"], input[name="username"], input[placeholder*="email" i]').first
      email_selector.fill(ENV['LOFTY_LOGIN_EMAIL'])
      
      # Try multiple possible selectors for password field
      password_selector = page.locator('input[type="password"], input[name="password"]').first
      password_selector.fill(ENV['LOFTY_LOGIN_PASSWORD'])
      
      # Try to find and click login button
      page.locator('button[type="submit"], button:has-text("Log in"), button:has-text("Sign in")').first.click

      puts "⏳ Waiting for login to complete..."
      sleep 10 # Wait for any redirects and page load

      context.storage_state(path: "tmp/lofty_storage_state.json")
      puts "🟢 Saved Lofty session → tmp/lofty_storage_state.json"

      browser.close
    end
  end
end
