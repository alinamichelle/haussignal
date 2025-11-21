# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[7.1].define(version: 2025_11_21_000408) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pgcrypto"
  enable_extension "plpgsql"

  create_table "agents", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "name", null: false
    t.string "email", null: false
    t.string "lofty_user_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["email"], name: "index_agents_on_email", unique: true
    t.index ["lofty_user_id"], name: "index_agents_on_lofty_user_id", unique: true
  end

  create_table "events", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "org_id", default: "realty-haus", null: false
    t.string "source", default: "lofty", null: false
    t.string "lofty_timeline_id", null: false
    t.integer "type_code", null: false
    t.string "event_type", null: false
    t.datetime "occurred_at", null: false
    t.datetime "edited_at"
    t.text "raw_text"
    t.jsonb "metadata", default: {}
    t.uuid "lead_id", null: false
    t.uuid "agent_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "email_category"
    t.index "((metadata ->> 'campaign_id'::text))", name: "index_events_on_campaign_id"
    t.index ["agent_id"], name: "index_events_on_agent_id"
    t.index ["event_type"], name: "index_events_on_event_type"
    t.index ["lead_id"], name: "index_events_on_lead_id"
    t.index ["lofty_timeline_id"], name: "index_events_on_lofty_timeline_id", unique: true
    t.index ["occurred_at"], name: "index_events_on_occurred_at"
  end

  create_table "leads", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "org_id", default: "realty-haus", null: false
    t.string "lofty_lead_id", null: false
    t.string "full_name"
    t.string "first_name"
    t.string "last_name"
    t.string "email"
    t.string "phone"
    t.string "status"
    t.string "source"
    t.text "tags", default: [], array: true
    t.uuid "agent_id"
    t.datetime "created_at_lofty"
    t.datetime "updated_at_lofty"
    t.datetime "last_synced_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "pipeline"
    t.string "segment"
    t.datetime "reg_date"
    t.string "lead_type"
    t.text "notes"
    t.datetime "timeline_synced_at"
    t.index ["agent_id"], name: "index_leads_on_agent_id"
    t.index ["lofty_lead_id"], name: "index_leads_on_lofty_lead_id", unique: true
    t.index ["timeline_synced_at"], name: "index_leads_on_timeline_synced_at"
  end

  add_foreign_key "events", "agents"
  add_foreign_key "events", "leads"
  add_foreign_key "leads", "agents"
end
