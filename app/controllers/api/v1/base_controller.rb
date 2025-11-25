module Api
  module V1
    class BaseController < ActionController::API
      # Skip auth by default - controllers opt-in
      # before_action :authenticate_user!

      attr_reader :current_user

      private

      # Extract and validate JWT from Authorization header
      def authenticate_user!
        header = request.headers['Authorization']
        token = header.split(' ').last if header
        
        if token
          decoded = JsonWebToken.decode(token)
          if decoded
            @current_user = User.find_by(id: decoded[:user_id])
            unless @current_user&.active?
              render json: { error: 'Unauthorized' }, status: :unauthorized
            end
          else
            render json: { error: 'Invalid token' }, status: :unauthorized
          end
        else
          render json: { error: 'Missing token' }, status: :unauthorized
        end
      end

      # Require admin role
      def require_admin!
        unless @current_user&.admin?
          render json: { error: 'Forbidden - Admin access required' }, status: :forbidden
        end
      end

      # Require admin or agent role
      def require_admin_or_agent!
        unless @current_user&.admin? || @current_user&.agent?
          render json: { error: 'Forbidden - Agent access required' }, status: :forbidden
        end
      end

      # Parse date range from request params
      # Returns a time range that can be used with occurred_at filtering
      def parsed_range
        case params[:range]
        when '7d'  then 7.days.ago..Time.current
        when '30d' then 30.days.ago..Time.current
        when '90d' then 90.days.ago..Time.current
        when '12m' then 12.months.ago..Time.current
        when 'ytd' then Time.current.beginning_of_year..Time.current
        when 'all' then Time.at(0)..Time.current
        when 'custom'
          # Custom date range from start_date and end_date params
          start_date = params[:start_date].present? ? Time.zone.parse(params[:start_date]).beginning_of_day : 30.days.ago
          end_date = params[:end_date].present? ? Time.zone.parse(params[:end_date]).end_of_day : Time.current
          start_date..end_date
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
