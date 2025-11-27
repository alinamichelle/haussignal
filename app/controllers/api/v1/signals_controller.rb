class Api::V1::SignalsController < ApplicationController
  # TODO: use real current_agent when auth is finalized
  before_action :require_agent!

  def index
    signals = HausSignal
      .where(agent_id: current_agent.id, status: "active")

    if params[:severity].present?
      severities = params[:severity].split(",").map(&:strip)
      signals = signals.where(severity: severities)
    end

    limit = (params[:limit].presence || 15).to_i.clamp(1, 100)

    signals = signals
      .includes(:lead)
      .order(Arel.sql("CASE severity WHEN 'high' THEN 3 WHEN 'medium' THEN 2 ELSE 1 END DESC"),
             last_seen_at: :desc)
      .limit(limit)

    render json: signals.map { |signal| serialize_signal(signal) }
  end

  def resolve
    signal = HausSignal.find(params[:id])
    # Optional: ensure signal.agent_id == current_agent.id
    signal.update!(status: "resolved")

    render json: serialize_signal(signal)
  end

  # GET /api/v1/signals/stats
  # Returns signal statistics across all agents (existing functionality)
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

  private

  def serialize_signal(signal)
    lead = signal.lead

    {
      id:              signal.id,
      signalType:      signal.signal_type,
      severity:        signal.severity,
      signalIcon:      signal.ui_icon,
      signalLabel:     signal.ui_label,
      description:     signal.ui_description,
      metadata:        signal.metadata || {},
      status:          signal.status,
      firstDetectedAt: signal.first_detected_at,
      lastSeenAt:      signal.last_seen_at,
      lead: lead && {
        id:            lead.id,
        name:          lead.full_name,
        email:         lead.email,
        phone:         lead.phone,
        pipelineStage: lead.pipeline_stage,
        leadType:      lead.lead_type
      }
    }
  end

  def require_agent!
    # TEMP: replace with real auth after Phase 1
    @current_agent = Agent.first if Rails.env.development?
  end

  def current_agent
    @current_agent
  end
end
