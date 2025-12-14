puts '=== ALL AGENTS - COMPLETE MANUAL ACTIVITY BREAKDOWN ==='

# Manual activity types to check
manual_types = ['call', 'note', 'sms', 'task']

agent_stats = {}

manual_types.each do |activity_type|
  puts "Analyzing #{activity_type} activities..."

  events = Event.where(event_type: activity_type)

  events.find_each(batch_size: 1000) do |event|
    performer = 'Unknown'

    if event.metadata && event.metadata['raw_json']
      begin
        raw_data = JSON.parse(event.metadata['raw_json'])
        if raw_data['fromFirstName'] && raw_data['fromLastName']
          performer = "#{raw_data['fromFirstName']} #{raw_data['fromLastName']}"
        end
      rescue
      end
    end

    # Only count known performers (actual agents)
    if performer != 'Unknown'
      agent_stats[performer] ||= { 'call' => 0, 'note' => 0, 'sms' => 0, 'task' => 0 }
      agent_stats[performer][activity_type] += 1
    end
  end
end

# Display results
puts "\n=== COMPLETE MANUAL ACTIVITY BREAKDOWN BY AGENT ===\n"
puts "Agent".ljust(25) + "Calls".rjust(8) + "Notes".rjust(8) + "SMS".rjust(8) + "Tasks".rjust(8) + "Total".rjust(8)
puts "-" * 73

agent_stats.sort_by { |agent, stats| -(stats.values.sum) }.each do |agent, stats|
  total = stats.values.sum
  puts "#{agent.ljust(25)}#{stats['call'].to_s.rjust(8)}#{stats['note'].to_s.rjust(8)}#{stats['sms'].to_s.rjust(8)}#{stats['task'].to_s.rjust(8)}#{total.to_s.rjust(8)}"
end

# Show totals
total_calls = agent_stats.values.map { |s| s['call'] }.sum
total_notes = agent_stats.values.map { |s| s['note'] }.sum
total_sms = agent_stats.values.map { |s| s['sms'] }.sum
total_tasks = agent_stats.values.map { |s| s['task'] }.sum
grand_total = total_calls + total_notes + total_sms + total_tasks

puts "-" * 73
puts "TOTALS".ljust(25) + total_calls.to_s.rjust(8) + total_notes.to_s.rjust(8) + total_sms.to_s.rjust(8) + total_tasks.to_s.rjust(8) + grand_total.to_s.rjust(8)