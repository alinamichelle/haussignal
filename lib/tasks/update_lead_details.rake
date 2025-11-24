require 'csv'

namespace :haussignal do
  desc "Update pipeline, source, and agent for existing leads from LoftyLead CSV (only matching IDs)"
  task :update_lead_details, [:csv_path] => :environment do |t, args|
    csv_path = args[:csv_path] || Rails.root.join('tmp/LoftyLead_11222025_jWZ3WVpZMrVuCWqe.csv')
    
    unless File.exist?(csv_path)
      puts "❌ File not found: #{csv_path}"
      exit 1
    end
    
    puts "📂 Updating lead details from: #{csv_path}"
    puts "   NOTE: Only updating leads that exist in BOTH database AND CSV"
    puts "=" * 60
    
    updated = 0
    skipped_not_found = 0
    skipped_no_changes = 0
    failed = []
    
    CSV.foreach(csv_path, headers: true, liberal_parsing: true) do |row|
      begin
        # LoftyLead CSV wraps Lead ID in backticks
        lofty_lead_id = row['Lead Id']&.strip&.gsub(/`/, '')
        
        if lofty_lead_id.blank?
          next
        end
        
        # ONLY update if lead already exists - don't create new ones
        lead = Lead.find_by(lofty_lead_id: lofty_lead_id)
        
        unless lead
          skipped_not_found += 1
          next
        end
        
        # Extract agent name
        agent_name = row['Assigned Agent']&.strip
        agent = nil
        if agent_name.present?
          # Find existing agent or create new one
          agent = Agent.find_by("name ILIKE ?", agent_name)
          unless agent
            # Create agent if doesn't exist
            agent = Agent.create!(
              org_id: ENV.fetch('ORG_ID', 'realty-haus'),
              name: agent_name,
              email: "#{agent_name.downcase.gsub(/\s+/, '.')}@realtyhaus.com"
            )
            puts "  ➕ Created agent: #{agent_name}"
          end
        end
        
        # Prepare updates
        updates = {}
        
        pipeline = row['Pipeline']&.strip
        source = row['Source']&.strip
        segment = row['Segment']&.strip
        
        updates[:pipeline] = pipeline if pipeline.present? && lead.pipeline != pipeline
        updates[:source] = source if source.present? && lead.source != source
        updates[:segment] = segment if segment.present? && lead.segment != segment
        updates[:agent_id] = agent&.id if agent && lead.agent_id != agent.id
        
        if updates.any?
          lead.update!(updates)
          updated += 1
          changes = updates.keys.join(', ')
          puts "✅ Updated #{lead.full_name} (#{lofty_lead_id}): #{changes}"
        else
          skipped_no_changes += 1
        end
        
      rescue => e
        failed << { lead_id: lofty_lead_id, error: e.message }
        puts "❌ Failed: #{lofty_lead_id} - #{e.message}"
      end
    end
    
    puts "=" * 60
    puts "✅ Update complete!"
    puts "   Updated: #{updated}"
    puts "   Skipped (not in DB): #{skipped_not_found}"
    puts "   Skipped (no changes): #{skipped_no_changes}"
    puts "   Failed: #{failed.size}"
    
    if failed.any?
      puts "\n⚠️  Failures:"
      failed.each do |f|
        puts "  - #{f[:lead_id]}: #{f[:error]}"
      end
    end
  end
end
