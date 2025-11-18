require 'net/http'
require 'json'

module Lofty
  module Clients
    class LeadClient
      BASE_URL = ENV.fetch("LOFTY_API_BASE_URL", "https://api.lofty.com")

      def initialize(api_key: ENV["LOFTY_API_KEY"])
        @api_key = api_key
      end

      def fetch_all_leads
        page = 1
        per_page = 100
        results = []

        loop do
          batch = fetch_page(page: page, per_page: per_page)
          break if batch.empty?

          results.concat(batch)
          page += 1
          
          # Safety limit for testing
          break if page > 100
        end

        results
      end

      private

      def fetch_page(page:, per_page:)
        # TODO: Implement actual Lofty API call
        # For now, return empty array (Phase 1 Sprint 1)
        
        uri = URI("#{BASE_URL}/v1.0/leads")
        uri.query = URI.encode_www_form({
          page: page,
          per_page: per_page
        })

        request = Net::HTTP::Get.new(uri)
        request['Authorization'] = "Bearer #{@api_key}"
        request['Content-Type'] = 'application/json'

        response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: uri.scheme == 'https') do |http|
          http.request(request)
        end

        if response.is_a?(Net::HTTPSuccess)
          data = JSON.parse(response.body)
          normalize_leads(data)
        else
          Rails.logger.error "Lofty API error: #{response.code} #{response.body}"
          []
        end
      rescue => e
        Rails.logger.error "Lofty API exception: #{e.message}"
        []
      end

      def normalize_leads(api_response)
        # Normalize Lofty API response into our format
        # Expected structure depends on actual Lofty API
        leads = api_response['leads'] || api_response['data'] || []
        
        leads.map do |lead_data|
          {
            lofty_lead_id: lead_data['id']&.to_s,
            full_name: lead_data['full_name'] || "#{lead_data['first_name']} #{lead_data['last_name']}".strip,
            first_name: lead_data['first_name'],
            last_name: lead_data['last_name'],
            email: lead_data['email'],
            phone: lead_data['phone'],
            status: lead_data['status'],
            source: lead_data['source'],
            tags: lead_data['tags'] || [],
            created_at_lofty: parse_api_timestamp(lead_data['created_at']),
            updated_at_lofty: parse_api_timestamp(lead_data['updated_at'])
          }
        end
      end

      def parse_api_timestamp(timestamp_str)
        return nil if timestamp_str.blank?
        Time.zone.parse(timestamp_str)
      rescue
        nil
      end
    end
  end
end
