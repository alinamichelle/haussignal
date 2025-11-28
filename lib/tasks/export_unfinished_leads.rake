require 'csv'
require 'fileutils'

namespace :sync do
  desc "Export unfinished leads from slots 1 and 2 to CSV files"
  task export_unfinished_leads: :environment do
    puts "🔍 Finding unfinished leads from slots 1 and 2..."

    # Get unfinished leads from slots 1 and 2
    unfinished_1 = Lead.where(sync_slot: 1, timeline_synced_at: nil)
                      .includes(:agent)

    unfinished_2 = Lead.where(sync_slot: 2, timeline_synced_at: nil)
                      .includes(:agent)

    timestamp = Time.current.strftime("%Y%m%d_%H%M%S")

    # Export slot 1 unfinished leads
    if unfinished_1.any?
      filename_1 = "exports/unfinished_slot_1_leads_#{timestamp}.csv"
      FileUtils.mkdir_p(File.dirname(filename_1))

      CSV.open(filename_1, 'w', write_headers: true, headers: [
        'id', 'lofty_lead_id', 'full_name', 'first_name', 'last_name', 'email', 'agent_name', 'created_at'
      ]) do |csv|
        unfinished_1.each do |lead|
          csv << [
            lead.id,
            lead.lofty_lead_id,
            lead.full_name,
            lead.first_name,
            lead.last_name,
            lead.email,
            lead.agent&.name,
            lead.created_at
          ]
        end
      end

      puts "📄 Slot 1: #{unfinished_1.count} unfinished leads exported to #{filename_1}"
    else
      puts "✅ Slot 1: No unfinished leads found!"
    end

    # Export slot 2 unfinished leads
    if unfinished_2.any?
      filename_2 = "exports/unfinished_slot_2_leads_#{timestamp}.csv"
      FileUtils.mkdir_p(File.dirname(filename_2))

      CSV.open(filename_2, 'w', write_headers: true, headers: [
        'id', 'lofty_lead_id', 'full_name', 'first_name', 'last_name', 'email', 'agent_name', 'created_at'
      ]) do |csv|
        unfinished_2.each do |lead|
          csv << [
            lead.id,
            lead.lofty_lead_id,
            lead.full_name,
            lead.first_name,
            lead.last_name,
            lead.email,
            lead.agent&.name,
            lead.created_at
          ]
        end
      end

      puts "📄 Slot 2: #{unfinished_2.count} unfinished leads exported to #{filename_2}"
    else
      puts "✅ Slot 2: No unfinished leads found!"
    end

    # Summary
    total_unfinished = unfinished_1.count + unfinished_2.count
    puts ""
    puts "📊 Summary:"
    puts "  Slot 1 unfinished: #{unfinished_1.count}"
    puts "  Slot 2 unfinished: #{unfinished_2.count}"
    puts "  Total unfinished: #{total_unfinished}"
    puts ""
    puts "💡 These leads can be tackled later after slots 0 and 3 are complete."
    puts "   They might have data issues or require special handling."
  end
end