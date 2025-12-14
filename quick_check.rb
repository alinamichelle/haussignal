tasks = Event.where(event_type: 'task').limit(50)

tasks.each do |task|
  lead = task.lead
  lead_owner = lead&.agent&.name || 'No Agent'

  performer = 'Unknown'
  if task.metadata && task.metadata['raw_json']
    begin
      raw_data = JSON.parse(task.metadata['raw_json'])
      if raw_data['fromFirstName'] && raw_data['fromLastName']
        performer = "#{raw_data['fromFirstName']} #{raw_data['fromLastName']}"
      end
    rescue
    end
  end

  if lead_owner != performer && performer != 'Unknown'
    puts "#{performer} did task on #{lead_owner}'s lead"
  end
end