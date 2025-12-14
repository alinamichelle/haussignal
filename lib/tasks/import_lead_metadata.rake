require 'csv'

namespace :leads do
  desc "Import lead metadata from CSV (lead_type, pipeline, source, reg_date, tags, csv_notes)"
  task :import_metadata, [:csv_path] => :environment do |t, args|
    csv_path = args[:csv_path] || 'tmp/LoftyLeads12:14:25.csv'
    
    unless File.exist?(csv_path)
      puts "❌ CSV file not found: #{csv_path}"
      exit 1
    end
    
    puts "📁 Reading CSV: #{csv_path}"
    
    stats = {
      processed: 0,
      updated: 0,
      not_found: 0,
      errors: 0,
      skipped: 0
    }
    
    CSV.foreach(csv_path, headers: true, liberal_parsing: true) do |row|
      stats[:processed] += 1
      
      # Get Lead ID from CSV (using backticks format: `1131410008210783`)
      lofty_lead_id = row['Lead Id']&.gsub(/[`\s]/, '')
      
      if lofty_lead_id.blank?
        stats[:skipped] += 1
        next
      end
      
      # Find lead in database
      lead = Lead.find_by(lofty_lead_id: lofty_lead_id)
      
      unless lead
        stats[:not_found] += 1
        if stats[:processed] <= 5
          puts "⚠️  Lead not found: #{lofty_lead_id}"
        end
        next
      end
      
      begin
        # Prepare update attributes
        updates = {}
        
        # Lead Type
        if row['Lead Type'].present?
          updates[:lead_type] = row['Lead Type'].strip
        end
        
        # Pipeline
        if row['Pipeline'].present?
          updates[:pipeline] = row['Pipeline'].strip
        end
        
        # Source
        if row['Source'].present?
          updates[:source] = row['Source'].strip
        end
        
        # Registration Date - parse "August 20 2016" format
        if row['Reg Date'].present?
          begin
            updates[:reg_date] = Date.parse(row['Reg Date'])
          rescue Date::Error => e
            puts "⚠️  Invalid date format for lead #{lofty_lead_id}: #{row['Reg Date']}"
          end
        end
        
        # Tags - split by pipe "|"
        if row['Tag'].present?
          tag_string = row['Tag'].strip
          if tag_string.include?('|')
            updates[:tags] = tag_string.split('|').map(&:strip).reject(&:blank?)
          else
            updates[:tags] = [tag_string]
          end
        end
        
        # CSV Notes - only Note 1
        if row['Note 1'].present?
          updates[:csv_notes] = row['Note 1'].strip
        end
        
        # Update lead if we have any changes
        if updates.any?
          lead.update!(updates)
          stats[:updated] += 1
          
          # Show first 3 updates as examples
          if stats[:updated] <= 3
            puts "✅ Updated lead #{lofty_lead_id} (#{lead.full_name}): #{updates.keys.join(', ')}"
          end
        else
          stats[:skipped] += 1
        end
        
      rescue StandardError => e
        stats[:errors] += 1
        puts "❌ Error updating lead #{lofty_lead_id}: #{e.message}"
      end
      
      # Progress indicator every 500 rows
      if stats[:processed] % 500 == 0
        puts "📊 Progress: #{stats[:processed]} processed, #{stats[:updated]} updated, #{stats[:not_found]} not found"
      end
    end
    
    # Final summary
    puts "\n" + "="*60
    puts "📊 Import Summary:"
    puts "="*60
    puts "Processed:  #{stats[:processed]}"
    puts "Updated:    #{stats[:updated]}"
    puts "Not Found:  #{stats[:not_found]}"
    puts "Skipped:    #{stats[:skipped]}"
    puts "Errors:     #{stats[:errors]}"
    puts "="*60
  end
end
