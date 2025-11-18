namespace :haussignal do
  desc "Sync leads from Lofty API (Phase 1)"
  task lead_sync: :environment do
    result = Lofty::Sync::LeadSyncService.new.call
    puts "\n✅ Lead sync complete!"
    puts "   Created: #{result[:created]}"
    puts "   Updated: #{result[:updated]}"
    puts "   Unchanged: #{result[:unchanged]}"
  end
end
