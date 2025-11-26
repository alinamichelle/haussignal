module Api
  module V1
    class SignalsController < BaseController
      # GET /api/v1/agents/:agent_id/signals
      # Returns active signals for an agent with lead details
      def index
        agent = Agent.find(params[:agent_id])
        
        signals = HausSignal
          .where(agent_id: agent.id, status: 'active')
          .includes(:lead)
          .order('severity DESC, last_seen_at DESC')
          .limit(100)
        
        signals_data = signals.map do |signal|
          {
            id: signal.id,
            lead: {
              id: signal.lead.id,
              name: signal.lead.full_name || [signal.lead.first_name, signal.lead.last_name].compact.join(' '),
              email: signal.lead.email,
              phone: signal.lead.phone,
              pipeline: signal.lead.pipeline
            },
            agent: {
              id: agent.id,
              name: agent.name
            },
            signalType: signal.signal_type,
            signalLabel: signal.ui_label,
            signalDescription: signal.ui_description,
            signalIcon: signal.ui_icon,
            severity: signal.severity,
            status: signal.status,
            firstDetectedAt: signal.first_detected_at,
            lastSeenAt: signal.last_seen_at,
            metadata: signal.metadata
          }
        end
        
        render json: {
          signals: signals_data,
          count: signals.size
        }
      end
      
      # GET /api/v1/signals/stats
      # Returns signal statistics across all agents
      def stats
        total = HausSignal.active.count
        by_type = HausSignal.active.group(:signal_type).count
        by_severity = HausSignal.active.group(:severity).count
        
        render json: {
          totalActive: total,
          byType: by_type,
          bySeverity: by_severity
        }
      end
    end
  end
end
