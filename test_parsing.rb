puts "Testing CanonicalClassifier..."
result = Lofty::CanonicalClassifier.classify(type_code: 25, raw_text: "Matt called Will", parsed_event: {})
puts "Result: #{result.inspect}"
puts "Testing TimelineParser TYPE_CODE_MAPPINGS..."
mapped = Lofty::TimelineParser::TYPE_CODE_MAPPINGS[25]
puts "Type 25 maps to: #{mapped.inspect}"
