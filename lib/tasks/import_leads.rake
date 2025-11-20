require 'csv'

namespace :haussignal do
  desc "Import leads from CSV file"
  task :import_leads, [:csv_path] => :environment do |t, args|
    csv_path = args[:csv_path] || Rails.root.join('tmp/unsubs_2025_11_25.csv')
    
    unless File.exist?(csv_path)
      puts "❌ File not found: #{csv_path}"
      exit 1
    end
    
    puts "📂 Importing leads from: #{csv_path}"
    puts "=" * 60
    
    created = 0
    updated = 0
    failed = []
    
    CSV.foreach(csv_path, headers: true, header_converters: :symbol) do |row|
      begin
        lofty_lead_id = row[:lead_id]&.strip
        
        if lofty_lead_id.blank?
          puts "⚠️  Skipping row with no Lead ID"
          next
        end
        
        # Find or create agent by name
        agent_name = row[:assigned_agent]&.strip
        agent = nil
        if agent_name.present?
          # Try to find existing agent or create placeholder
          agent = Agent.find_by("name ILIKE ?", agent_name)
          unless agent
            # Create agent with placeholder email
            email = "#{agent_name.downcase.gsub(/\s+/, '.')}@realtyhaus.com"
            agent = Agent.find_or_create_by!(email: email) do |a|
              a.name = agent_name
            end
            puts "  ➕ Created agent: #{agent_name}"
          end
        end
        
        # Find or create lead
        lead = Lead.find_or_initialize_by(lofty_lead_id: lofty_lead_id)
        is_new = lead.new_record?
        
        lead.assign_attributes(
          org_id: ENV.fetch('ORG_ID', 'realty-haus'),
          first_name: row[:first_name]&.strip,
          last_name: row[:last_name]&.strip,
          full_name: "#{row[:first_name]&.strip} #{row[:last_name]&.strip}".strip.presence,
          lead_type: row[:lead_type]&.strip,
          email: row[:primary_email]&.strip,
          phone: row[:primary_phone]&.strip,
          notes: row[:note_1]&.strip,
          agent_id: agent&.id
        )
        
        lead.save!
        
        if is_new
          created += 1
          puts "✅ Created: #{lead.full_name} (#{lofty_lead_id})"
        else
          updated += 1
          puts "🔄 Updated: #{lead.full_name} (#{lofty_lead_id})"
        end
        
      rescue => e
        failed << { lead_id: lofty_lead_id, error: e.message }
        puts "❌ Failed: #{lofty_lead_id} - #{e.message}"
      end
    end
    
    puts "=" * 60
    puts "✅ Import complete!"
    puts "   Created: #{created}"
    puts "   Updated: #{updated}"
    puts "   Failed: #{failed.size}"
    
    if failed.any?
      puts "\n⚠️  Failures:"
      failed.each do |f|
        puts "  - #{f[:lead_id]}: #{f[:error]}"
      end
    end
  end
end
