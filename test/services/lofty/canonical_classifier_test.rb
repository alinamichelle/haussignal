require_relative "../../test_helper"

class CanonicalClassifierTest < Minitest::Test
  TEST_TYPE_CODES = [
    6,   # manual email
    8,   # inbound call
    25,  # outbound call
    37,  # alert email opened
    59,  # property viewed
    101, # smart plan applied
    103, # mixed handler (email or task)
    111, # manual unsubscribe
    124, # auto email sent
    169  # lead reassigned
  ].freeze

  def test_known_type_codes_always_return_category_and_channel
    TEST_TYPE_CODES.each do |code|
      result = Lofty::CanonicalClassifier.classify(
        type_code: code,
        raw_text: "",
        parsed_event: {}
      )

      refute_nil result[:category], "category nil for type_code=#{code}"
      refute_nil result[:channel],  "channel nil for type_code=#{code}"
    end
  end
end