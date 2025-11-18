namespace :lofty do
  desc "Login to Lofty and save storage state"
  task login: :environment do
    require 'playwright'

    Playwright.create(playwright_cli_executable_path: 'npx playwright') do |playwright|
      browser = playwright.chromium.launch(headless: false)
      context = browser.new_context
      page    = context.new_page

      puts "🔵 Opening Lofty..."
      page.goto(ENV['LOFTY_BASE_URL'])

      puts "🟡 Please log in manually. You have 60 seconds..."
      sleep 60

      context.storage_state(path: "tmp/lofty_storage_state.json")
      puts "🟢 Saved Lofty session → tmp/lofty_storage_state.json"

      browser.close
    end
  end
end
