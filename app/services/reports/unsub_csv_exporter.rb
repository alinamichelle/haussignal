# app/services/reports/unsub_csv_exporter.rb
require 'csv'

module Reports
  class UnsubCsvExporter
    def export_to_file(file_path)
      unsub_events = Event.where(event_type: 'unsub')
                          .includes(:lead, :agent)
                          .order('leads.lofty_lead_id, events.occurred_at')

      # Group by [lead_id, occurred_at] to create "sessions"
      # Multiple unsub events at same time = one session
      sessions = unsub_events.group_by do |event|
        [event.lead_id, event.occurred_at.change(usec: 0)]
      end

      CSV.open(file_path, 'w') do |csv|
        # Write header
        csv << [
          'lead_lofty_id',
          'lead_name',
          'agent_name',
          'pipeline',
          'segment',
          'source',
          'reg_date',
          'unsub_date',
          'unsub_time',
          'unsub_categories',
          'trigger_email_type',
          'trigger_email_subject',
          'trigger_email_from',
          'emails_sent_total',
          'emails_opened_total',
          'email_open_rate_percent',
          'lofty_lead_url'
        ]

        # Write data rows
        sessions.each do |(lead_id, occurred_at), events|
          session = build_session_row(events, lead_id)
          csv << session
        end
      end

      puts "✅ Exported #{sessions.size} unsub sessions to #{file_path}"
    end

    private

    def build_session_row(events, lead_id)
      # Take first event for shared fields
      event = events.first
      lead = event.lead
      agent = event.agent
      metadata = event.metadata || {}
      trigger = metadata['triggerEmail'] || {}

      # Merge categories from all events in session (pipe-separated)
      categories = events.map { |e| e.metadata['unsubCategory'] }.compact.uniq.join('|')

      # Calculate engagement stats for this lead
      engagement = calculate_engagement_stats(lead_id)

      [
        lead.lofty_lead_id,                                      # lead_lofty_id
        lead.full_name || "#{lead.first_name} #{lead.last_name}".strip, # lead_name
        agent&.name,                                             # agent_name
        lead.pipeline,                                           # pipeline
        lead.segment,                                            # segment
        lead.source,                                             # source
        format_date(lead.reg_date),                              # reg_date
        format_date(event.occurred_at),                          # unsub_date
        format_time(event.occurred_at),                          # unsub_time
        categories,                                              # unsub_categories
        trigger['emailType'],                                    # trigger_email_type
        trigger['emailSubject'],                                 # trigger_email_subject
        trigger['emailHeader'],                                  # trigger_email_from
        engagement[:sent],                                       # emails_sent_total
        engagement[:opened],                                     # emails_opened_total
        engagement[:rate],                                       # email_open_rate_percent
        lofty_lead_url(lead.lofty_lead_id)                       # lofty_lead_url
      ]
    end

    def calculate_engagement_stats(lead_id)
      sent_count = Event.where(lead_id: lead_id, event_type: 'email_sent').count
      opened_count = Event.where(lead_id: lead_id, event_type: 'email_opened').count

      rate = if sent_count > 0
               ((opened_count.to_f / sent_count) * 100).round(1)
             else
               0.0
             end

      {
        sent: sent_count,
        opened: opened_count,
        rate: rate
      }
    end

    def format_date(datetime)
      return nil if datetime.nil?
      datetime.strftime('%Y-%m-%d')
    end

    def format_time(datetime)
      return nil if datetime.nil?
      datetime.strftime('%H:%M:%S')
    end

    def lofty_lead_url(lofty_lead_id)
      "https://crm.lofty.com/admin/home/detail?leadId=#{lofty_lead_id}"
    end
  end
end
