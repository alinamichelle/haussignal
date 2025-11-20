# lib/tasks/unsub_export.rake
namespace :haussignal do
  desc "Export unsubscribe data to CSV"
  task :export_unsubs_csv, [:output_path] => :environment do |t, args|
    output_path = args[:output_path] || 'tmp/unsubs_export.csv'
    
    puts "📊 Exporting unsub data to CSV..."
    puts "   Output: #{output_path}"
    
    exporter = Reports::UnsubCsvExporter.new
    exporter.export_to_file(output_path)
    
    puts "✅ Done!"
  end
end
