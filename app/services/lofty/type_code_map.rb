# frozen_string_literal: true

module Lofty
  class TypeCodeMap
    MAP = {
      # =========================================================
      # COMMUNICATION (Manual / Lead-Initiated / AI Assist)
      # =========================================================

      6   => {
        event_type:         :email_sent_manual,
        category:           :communication,
        communication_kind: :manual,
        channel:            :email,
        auto:               false,
        direction:          :outbound,
        source:             'lofty'
      },

      8   => {
        event_type:         :call_received,
        category:           :communication,
        communication_kind: :lead_initiated,
        channel:            :call,
        auto:               false,
        direction:          :inbound,
        source:             'lofty'
      },

      25  => {
        event_type:         :call_made,
        category:           :communication,
        communication_kind: :manual,
        channel:            :call,
        auto:               false,
        direction:          :outbound,
        source:             'lofty'
      },

      87  => {
        event_type:         :call_made,
        category:           :communication,
        communication_kind: :manual,
        channel:            :call,
        auto:               false,
        direction:          :outbound,
        source:             'lofty'
      },

      24  => {
        event_type:         :sms_sent_manual,
        category:           :communication,
        communication_kind: :manual,
        channel:            :sms,
        auto:               false,
        direction:          :outbound,
        source:             'lofty'
      },

      65  => {
        event_type:         :lead_message_left,
        category:           :communication,
        communication_kind: :lead_initiated,
        channel:            :website,
        auto:               true,
        direction:          :inbound,
        source:             'lofty'
      },

      118 => {
        event_type:         :chatbox_message_sent,
        category:           :communication,
        communication_kind: :lead_initiated,
        channel:            :website,
        auto:               true,
        direction:          :inbound,
        source:             'lofty'
      },

      119 => {
        event_type:         :zillow_message_left,
        category:           :communication,
        communication_kind: :lead_initiated,
        channel:            :website,
        auto:               true,
        direction:          :inbound,
        source:             'lofty'
      },

      142 => {
        event_type:         :sms_sent_manual,
        category:           :communication,
        communication_kind: :manual,
        channel:            :sms,
        auto:               false,
        direction:          :outbound,
        source:             'lofty'
      },

      186 => {
        event_type:         :sms_sent_group,
        category:           :communication,
        communication_kind: :manual,
        channel:            :sms,
        auto:               false,
        direction:          :outbound,
        source:             'lofty'
      },

      126 => {
        event_type:         :ai_question_asked,
        category:           :communication,
        communication_kind: :ai_assist,
        channel:            :system,
        auto:               true,
        source:             'lofty'
      },

      150 => {
        event_type:         :ai_call_transferred,
        category:           :communication,
        communication_kind: :ai_assist,
        channel:            :call,
        auto:               true,
        direction:          :inbound,
        source:             'lofty'
      },

      190 => {
        event_type:         :ai_call_received,
        category:           :communication,
        communication_kind: :lead_initiated,
        channel:            :call,
        auto:               true,
        direction:          :inbound,
        source:             'lofty'
      },

      # =========================================================
      # MARKETING (Outbound Campaigns, Engagement, Lead Behavior)
      # =========================================================

      5   => {
        event_type:     :email_opened,
        category:       :marketing,
        marketing_kind: :engagement,
        channel:        :email,
        auto:           true,
        source:         'lofty'
      },

      37  => {
        event_type:     :alert_email_opened,
        category:       :marketing,
        marketing_kind: :engagement,
        channel:        :email,
        auto:           true,
        source:         'lofty'
      },

      124 => {
        event_type:     :alert_email_sent,
        category:       :marketing,
        marketing_kind: :outbound,
        channel:        :email,
        auto:           true,
        source:         'lofty'
      },

      128 => {
        event_type:     :market_snapshot_email_sent,
        category:       :marketing,
        marketing_kind: :outbound,
        channel:        :email,
        auto:           true,
        source:         'lofty'
      },

      131 => {
        event_type:     :market_snapshot_email_opened,
        category:       :marketing,
        marketing_kind: :engagement,
        channel:        :email,
        auto:           true,
        source:         'lofty'
      },

      125 => {
        event_type:     :sms_sent_auto,
        category:       :marketing,
        marketing_kind: :outbound,
        channel:        :sms,
        auto:           true,
        source:         'lofty'
      },

      9   => {
        event_type:     :property_saved,
        category:       :marketing,
        marketing_kind: :engagement,
        channel:        :website,
        auto:           true,
        source:         'lofty'
      },

      10  => {
        event_type:     :listing_searched,
        category:       :marketing,
        marketing_kind: :engagement,
        channel:        :website,
        auto:           true,
        source:         'lofty'
      },

      59  => {
        event_type:     :property_viewed,
        category:       :marketing,
        marketing_kind: :engagement,
        channel:        :website,
        auto:           true,
        source:         'lofty'
      },

      89  => {
        event_type:     :mortgage_calculator_used,
        category:       :marketing,
        marketing_kind: :engagement,
        channel:        :website,
        auto:           true,
        source:         'lofty'
      },

      154 => {
        event_type:     :property_unsaved,
        category:       :marketing,
        marketing_kind: :engagement,
        channel:        :website,
        auto:           true,
        source:         'lofty'
      },

      66  => {
        event_type:     :showing_requested,
        category:       :marketing,
        marketing_kind: :engagement,
        channel:        :website,
        auto:           true,
        source:         'lofty'
      },

      143 => {
        event_type:     :landing_page_registered,
        category:       :marketing,
        marketing_kind: :engagement,
        channel:        :website,
        auto:           true,
        source:         'lofty'
      },

      148 => {
        event_type:     :website_form_submitted,
        category:       :marketing,
        marketing_kind: :engagement,
        channel:        :website,
        auto:           true,
        source:         'lofty'
      },

      79  => {
        event_type:     :market_snapshot_scheduled,
        category:       :marketing,
        marketing_kind: :outbound,
        channel:        :system,
        auto:           true,
        source:         'lofty'
      },

      83  => {
        event_type:     :newsletter_sent,
        category:       :marketing,
        marketing_kind: :outbound,
        channel:        :email,
        auto:           true,
        source:         'lofty'
      },

      46  => {
        event_type:     :sell_request_submitted,
        category:       :marketing,
        marketing_kind: :engagement,
        channel:        :website,
        auto:           true,
        source:         'lofty'
      },

      47  => {
        event_type:     :home_evaluation_requested,
        category:       :marketing,
        marketing_kind: :engagement,
        channel:        :website,
        auto:           true,
        source:         'lofty'
      },

      91  => {
        event_type:     :market_report_scheduled,
        category:       :marketing,
        marketing_kind: :outbound,
        channel:        :system,
        auto:           false,
        source:         'lofty'
      },

      160 => {
        event_type:     :cma_report_requested_website,
        category:       :marketing,
        marketing_kind: :engagement,
        channel:        :website,
        auto:           true,
        source:         'lofty'
      },

      162 => {
        event_type:     :cma_report_requested_home_report,
        category:       :marketing,
        marketing_kind: :engagement,
        channel:        :website,
        auto:           true,
        source:         'lofty'
      },

      11  => {
        handler: :handle_11
      },

      # =========================================================
      # TASKS
      # =========================================================

      1   => {
        event_type:   :task_created,
        category:     :task,
        task_origin:  :ad_hoc,
        channel:      :system,
        auto:         false,
        source:       'lofty'
      },

      2   => {
        event_type:   :task_edited,
        category:     :task,
        task_origin:  :ad_hoc,
        channel:      :system,
        auto:         false,
        source:       'lofty'
      },

      3   => {
        event_type:   :task_deleted,
        category:     :task,
        task_origin:  :ad_hoc,
        channel:      :system,
        auto:         false,
        source:       'lofty'
      },

      104 => {
        event_type:   :task_completed_manual,
        category:     :task,
        task_origin:  :ad_hoc,
        channel:      :system,
        auto:         false,
        source:       'lofty'
      },

      105 => {
        event_type:   :task_completed_auto,
        category:     :task,
        task_origin:  :smart_plan,
        channel:      :system,
        auto:         true,
        source:       'lofty'
      },

      41  => {
        event_type:   :showing_request_deleted,
        category:     :task,
        task_origin:  :ad_hoc,
        channel:      :system,
        auto:         false,
        source:       'lofty'
      },

      # =========================================================
      # SMART PLANS
      # =========================================================

      101 => {
        event_type: :smart_plan_applied,
        category:   :smart_plan,
        channel:    :system,
        auto:       false,
        source:     'lofty'
      },

      102 => {
        event_type: :smart_plan_deleted,
        category:   :smart_plan,
        channel:    :system,
        auto:       false,
        source:     'lofty'
      },

      103 => {
        handler: :handle_103
      },

      170 => {
        handler: :handle_170
      },

      # =========================================================
      # PROFILE / LEAD RECORD CHANGES
      # =========================================================

      7   => {
        event_type:          :note_added,
        category:            :profile,
        profile_change_type: :note_change,
        channel:             :system,
        auto:                false,
        source:              'lofty'
      },

      16  => {
        event_type:          :note_added,
        category:            :profile,
        profile_change_type: :note_change,
        channel:             :system,
        auto:                false,
        source:              'lofty'
      },

      21  => {
        event_type:          :contact_info_updated,
        category:            :profile,
        profile_change_type: :contact_info_change,
        channel:             :system,
        auto:                false,
        source:              'lofty'
      },

      31  => {
        event_type:          :lead_assigned,
        category:            :profile,
        profile_change_type: :assignment_change,
        channel:             :system,
        auto:                false,
        source:              'lofty'
      },

      38  => {
        event_type:          :pipeline_stage_changed,
        category:            :profile,
        profile_change_type: :pipeline_change,
        channel:             :system,
        auto:                false,
        source:              'lofty'
      },

      64  => {
        event_type:          :lead_assigned_auto,
        category:            :profile,
        profile_change_type: :assignment_change,
        channel:             :system,
        auto:                true,
        source:              'lofty'
      },

      67  => {
        event_type:          :lead_registered,
        category:            :profile,
        profile_change_type: :source_update,
        channel:             :website,
        auto:                true,
        source:              'lofty'
      },

      68  => {
        event_type:          :lead_added_manual,
        category:            :profile,
        profile_change_type: :source_update,
        channel:             :system,
        auto:                false,
        source:              'lofty'
      },

      69  => {
        event_type:          :lead_imported_zillow,
        category:            :profile,
        profile_change_type: :source_update,
        channel:             :system,
        auto:                true,
        source:              'lofty'
      },

      71  => {
        event_type:          :lead_imported_csv,
        category:            :profile,
        profile_change_type: :source_update,
        channel:             :system,
        auto:                false,
        source:              'lofty'
      },

      93  => {
        event_type:          :contact_info_updated,
        category:            :profile,
        profile_change_type: :contact_info_change,
        channel:             :system,
        auto:                true,
        source:              'lofty'
      },

      97  => {
        event_type:          :lead_merged,
        category:            :profile,
        profile_change_type: :ownership_transfer,
        channel:             :system,
        auto:                false,
        source:              'lofty'
      },

      120 => {
        event_type:          :property_edited,
        category:            :profile,
        profile_change_type: :note_change,
        channel:             :system,
        auto:                false,
        source:              'lofty'
      },

      127 => {
        handler: :handle_127
      },

      134 => {
        event_type:          :ai_note_added,
        category:            :profile,
        profile_change_type: :note_change,
        channel:             :system,
        auto:                true,
        source:              'lofty'
      },

      135 => {
        event_type:          :ai_note_added,
        category:            :profile,
        profile_change_type: :note_change,
        channel:             :system,
        auto:                true,
        source:              'lofty'
      },

      169 => {
        event_type:          :lead_reassigned_auto,
        category:            :profile,
        profile_change_type: :assignment_change,
        channel:             :system,
        auto:                true,
        source:              'lofty'
      },

      200 => {
        event_type:          :contact_info_updated,
        category:            :profile,
        profile_change_type: :contact_info_change,
        channel:             :system,
        auto:                true,
        source:              'lofty'
      },

      22  => {
        event_type:          :lead_deleted,
        category:            :profile,
        profile_change_type: :ownership_transfer,
        channel:             :system,
        auto:                false,
        source:              'lofty'
      },

      74  => {
        event_type:          :lead_imported_phone_contacts,
        category:            :profile,
        profile_change_type: :source_update,
        channel:             :system,
        auto:                false,
        source:              'lofty'
      },

      # =========================================================
      # TRANSACTION
      # =========================================================

      116 => {
        event_type: :transaction_created,
        category:   :transaction,
        channel:    :system,
        auto:       false,
        source:     'lofty'
      },

      63  => {
        event_type: :lender_assigned,
        category:   :transaction,
        channel:    :system,
        auto:       false,
        source:     'lofty'
      },

      57  => {
        event_type: :document_uploaded,
        category:   :transaction,
        channel:    :system,
        auto:       false,
        source:     'lofty'
      },

      98  => {
        event_type:          :system_note_added,
        category:            :profile,
        profile_change_type: :note_change,
        channel:             :system,
        auto:                true,
        source:              'lofty'
      },

      # =========================================================
      # COMPLIANCE
      # =========================================================

      111 => {
        event_type: :email_unsubscribed_manual,
        category:   :compliance,
        channel:    :email,
        auto:       false,
        source:     'lofty'
      },

      113 => {
        event_type: :email_unsubscribed_auto,
        category:   :compliance,
        channel:    :email,
        auto:       true,
        source:     'lofty'
      },

      112 => {
        event_type: :email_resubscribed_manual,
        category:   :compliance,
        channel:    :email,
        auto:       false,
        source:     'lofty'
      },

      # =========================================================
      # SYSTEM INTERNAL / NOISE
      # =========================================================

      4   => {
        event_type: :system_noise,
        category:   :system_internal,
        channel:    :system,
        auto:       true,
        source:     'lofty'
      },

      28  => {
        event_type: :system_noise,
        category:   :system_internal,
        channel:    :system,
        auto:       true,
        source:     'lofty'
      },

      43  => {
        event_type: :system_noise,
        category:   :system_internal,
        channel:    :system,
        auto:       true,
        source:     'lofty'
      },

      86  => {
        event_type: :system_noise,
        category:   :system_internal,
        channel:    :system,
        auto:       true,
        source:     'lofty'
      },

      92  => {
        event_type: :system_noise,
        category:   :system_internal,
        channel:    :system,
        auto:       true,
        source:     'lofty'
      },

      123 => {
        event_type: :system_noise,
        category:   :system_internal,
        channel:    :system,
        auto:       true,
        source:     'lofty'
      },

      80  => {
        event_type: :external_spam_email,
        category:   :system_internal,
        channel:    :email,
        auto:       true,
        spam:       true,
        source:     'lofty'
      }
    }.freeze

    def self.lookup(code)
      mapping = MAP[code.to_i]

      if mapping.nil?
        Rails.logger.warn("[TypeCodeMap] Unknown Lofty type_code=#{code}")
        return {
          event_type: :unknown_event,
          category:   :system_internal,
          channel:    :system,
          auto:       true,
          source:     'lofty'
        }
      end

      mapping
    end
  end
end
