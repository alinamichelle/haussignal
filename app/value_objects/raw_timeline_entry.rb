class RawTimelineEntry
  attr_reader :lead_lofty_id, :event_id, :type_code, :timestamp_text, :raw_text, :audio_url

  def initialize(lead_lofty_id:, event_id:, type_code:, timestamp_text:, raw_text:, audio_url: nil)
    @lead_lofty_id  = lead_lofty_id
    @event_id       = event_id
    @type_code      = type_code
    @timestamp_text = timestamp_text
    @raw_text       = raw_text
    @audio_url      = audio_url
  end
end
