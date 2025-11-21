class AddPipelineAndRecordingFieldsToEvents < ActiveRecord::Migration[7.1]
  def change
    add_column :events, :from_pipeline, :string
    add_column :events, :to_pipeline, :string
    add_column :events, :recording_available, :boolean, default: false
  end
end
