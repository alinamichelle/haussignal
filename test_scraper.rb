puts 'Testing modified TimelineScraper with lead: 1142032162531031'
puts '=' * 60

begin
  scraper = Lofty::Scrapers::TimelineScraper.new
  result = scraper.scrape_all_for_lead('1142032162531031')

  puts 'SCRAPER RESULT:'
  puts '  Success: ' + result[:success].to_s
  puts '  Message: ' + result[:message].to_s
  puts '  Entries count: ' + (result[:entries] || []).length.to_s

  if result[:success] && result[:entries]&.any?
    puts ''
    puts 'SAMPLE ENTRIES (first 3):'
    result[:entries].first(3).each_with_index do |entry, i|
      puts "  #{i+1}. Type: #{entry.type_code}, Text: #{entry.raw_text&.truncate(60)}"
    end
  end

  if !result[:success]
    puts ''
    puts 'ERROR DETAILS:'
    puts '  ' + (result[:error]&.message || 'No error details')
  end

rescue => e
  puts 'RUBY ERROR:'
  puts '  ' + e.message
  puts '  ' + e.backtrace.first(5).join("\n  ")
end

puts "\n" + "=" * 60
puts "Test completed!"🚀 REAL-WORLD BATCH TEST - MONITORING MODE
