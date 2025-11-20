module Api
  module V1
    class BaseController < ActionController::API
      private

      # Parse date range from request params
      # Returns a time range that can be used with occurred_at filtering
      def parsed_range
        case params[:range]
        when '7d'  then 7.days.ago..Time.current
        when '30d' then 30.days.ago..Time.current
        when '90d' then 90.days.ago..Time.current
        when '12m' then 12.months.ago..Time.current
        when 'all' then Time.at(0)..Time.current
        else 30.days.ago..Time.current # default to 30d
        end
      end

      # Filter events by email_type stored in metadata
      def email_type_filter(scope)
        case params[:email_type]
        when 'mass'   then scope.where("metadata->>'emailType' = ?", 'mass')
        when 'manual' then scope.where("metadata->>'emailType' = ?", 'manual')
        when 'auto'   then scope.where("metadata->>'emailType' = ?", 'auto')
        else scope # 'all' or nil returns unfiltered scope
        end
      end

      # Build base event scope with all filters applied
      # This is the foundation for all dashboard queries
      def scoped_events
        scope = Event.where(occurred_at: parsed_range)
        scope = scope.where(agent_id: params[:agent_id]) if params[:agent_id].present?
        scope = scope.joins(:lead).where(leads: { pipeline: params[:pipeline] }) if params[:pipeline].present?
        email_type_filter(scope)
      end
    end
  end
end
