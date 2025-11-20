# app/controllers/debug/leads_controller.rb
module Debug
  class LeadsController < ActionController::Base
    # If you have auth, you might want to lock this down:
    # before_action :authenticate_admin!

    def index
      # Filter option: show only leads with unsubs or all leads
      @filter = params[:filter] || 'all' # 'all', 'unsub_only', 'auto_unsub', 'manual_unsub', 'pending'
      
      @q = Lead.all
      
      case @filter
      when 'unsub_only'
        @q = @q.left_joins(:events)
                .where(events: { event_type: ['unsub', 'manual_unsub'] })
                .distinct
      when 'auto_unsub'
        @q = @q.left_joins(:events)
                .where(events: { event_type: 'unsub' })
                .distinct
      when 'manual_unsub'
        @q = @q.left_joins(:events)
                .where(events: { event_type: 'manual_unsub' })
                .distinct
      when 'pending'
        @q = @q.left_joins(:events)
                .where(events: { id: nil })
      end
      
      @q = @q.order("leads.created_at DESC")

      # Pagination
      @page     = (params[:page] || 1).to_i
      @per_page = 50
      @total    = @q.count
      @leads    = @q.offset((@page - 1) * @per_page).limit(@per_page)
                   .includes(:events)
    end

    def show
      # Support both database UUID and lofty_lead_id
      @lead = if params[:id].match?(/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i)
                Lead.find(params[:id])
              else
                Lead.find_by!(lofty_lead_id: params[:id])
              end

      @events = @lead.events.order(:occurred_at)

      # For quick visual debugging
      @auto_unsubs    = @events.select { |e| e.event_type.to_s == "unsub" }
      @manual_unsubs  = @events.select { |e| e.event_type.to_s == "manual_unsub" }
      @unsubs         = @auto_unsubs + @manual_unsubs
      @email_sents    = @events.select { |e| e.event_type.to_s == "email_sent" }
      @email_opens    = @events.select { |e| e.event_type.to_s == "email_opened" }

      # Last "trigger email" per unsub (if your attribution has filled metadata)
      @unsub_with_triggers = @unsubs.map do |unsub|
        trigger = unsub.metadata["triggerEmail"] || {}
        {
          unsub:   unsub,
          trigger: trigger
        }
      end
    end
  end
end
