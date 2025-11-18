module Lofty
  module Sync
    class LeadSyncService
      def initialize(client: Lofty::Clients::LeadClient.new)
        @client = client
      end

      def call
        Rails.logger.info "🔄 Starting lead sync from Lofty API..."
        
        lofty_leads = @client.fetch_all_leads
        
        Rails.logger.info "📊 Fetched #{lofty_leads.length} leads from Lofty"
        
        stats = { created: 0, updated: 0, unchanged: 0 }

        lofty_leads.each do |attrs|
          next if attrs[:lofty_lead_id].blank?
          
          lead = Lead.find_or_initialize_by(lofty_lead_id: attrs[:lofty_lead_id])

          lead.assign_attributes(
            full_name: attrs[:full_name],
            first_name: attrs[:first_name],
            last_name: attrs[:last_name],
            email: attrs[:email],
            phone: attrs[:phone],
            status: attrs[:status],
            source: attrs[:source],
            tags: attrs[:tags] || [],
            created_at_lofty: attrs[:created_at_lofty],
            updated_at_lofty: attrs[:updated_at_lofty],
            last_synced_at: Time.current
          )

          if lead.new_record?
            lead.save!
            stats[:created] += 1
          elsif lead.changed?
            lead.save!
            stats[:updated] += 1
          else
            lead.touch(:last_synced_at)
            stats[:unchanged] += 1
          end
        end

        Rails.logger.info "✅ Lead sync complete: #{stats[:created]} new, #{stats[:updated]} updated, #{stats[:unchanged]} unchanged"
        
        stats
      end
    end
  end
end
