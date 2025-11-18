class RawTimelineEntry
  attr_reader :lead_lofty_id, :event_id, :type_code, :timestamp_text, :raw_text, :audio_url,
              :html_content, :data_attributes, :css_classes

  def initialize(
    lead_lofty_id:,
    event_id:,
    type_code:,
    timestamp_text:,
    raw_text:,
    audio_url: nil,
    html_content: nil,
    data_attributes: {},
    css_classes: []
  )
    @lead_lofty_id    = lead_lofty_id
    @event_id         = event_id
    @type_code        = type_code
    @timestamp_text   = timestamp_text
    @raw_text         = raw_text
    @audio_url        = audio_url
    @html_content     = html_content
    @data_attributes  = data_attributes || {}
    @css_classes      = css_classes || []
  end
end
