module Lofty
  class EmailCategoryClassifier
    # Define email categories and their matching patterns
    CATEGORIES = {
      # Event mass emails
      event_mass_email: [
        /haus huddle/i,
        /haus for the holidays/i,
        /crawfish boil/i,
        /crawfish.*cold drinks/i,
        /crawfish.*good time/i,
        /holiday party highlights/i,
        /you'?re invited.*night of soccer/i,
        /tailgate event/i,
        /haus event.*good cause/i,
        /checking in.*did you get.*invite/i
      ],
      
      # Home anniversary smart plan
      home_anniversary: [
        /haus-iversary/i,
        /hausiversary/i
      ],
      
      # Monthly newsletter
      monthly_newsletter: [
        /austin'?s monthly digest/i,
        /\w+'?s monthly digest/i,  # Matches any name's monthly digest (e.g., "Vanessa's Monthly Digest")
        /🗞️.*monthly digest/i      # Matches newsletter emoji + monthly digest
      ],
      
      # Seller welcome email
      seller_welcome: [
        /your haus,?\s*our commitment/i
      ],
      
      # Buyer welcome email
      buyer_welcome: [
        /haus hunting made easy/i
      ],
      
      # GRE intro/announcement
      gre_intro: [
        /gunn real estate.*realty haus/i,
        /gre.*realty haus.*join forces/i
      ],
      
      # Holiday emails
      holiday: [
        /celebrating the season/i,
        /happy holidays/i,
        /future of opportunities.*happy holidays/i,
        /you shaped our story/i
      ],
      
      # Broker open house
      broker_open: [
        /broker preview/i,
        /exclusive broker/i
      ],
      
      # Open house invite
      open_house_invite: [
        /do you like happy hours/i,
        /happy hour/i
      ],
      
      # Realty Haus intro
      rh_intro: [
        /meet realty haus/i,
        /our journey continues.*realty haus/i
      ],
      
      # Informational
      informational: [
        /are you.*home okay.*trusted pros/i,
        /last chance to protest taxes/i,
        /fyi.*protest taxes/i,
        /save on property taxes/i,
        /property taxes.*deadline/i,
        /mortgage rates.*back/i,
        /texas homeowners.*may 15 deadline/i,
        /recent successes.*austin real estate/i
      ],
      
      # Listing blast
      listing_blast: [
        /coming soon -/i,
        /deal of the week/i,
        /price improvement -/i,
        /final check-in.*rsvp.*private viewing/i,
        /new price on.*home/i,
        /luxury for less/i
      ],
      
      # Property alerts (also handled by listing_alert emailType)
      property_alert: [
        /\d+\s+new\s+homes?\s+for/i,           # Matches "4 New Homes for..." or "1 New Home for..."
        /new\s+homes?\s+for.*and\s+more/i,     # Matches "New Homes for ... and more"
        /\[price\s+reduced/i,
        /\[status\s+changed/i
      ],
      
      # Market snapshot / sold notifications
      market_snapshot: [
        /property in your area was just sold/i,
        /this property.*was just sold/i
      ]
    }.freeze

    def self.classify(subject, lofty_email_type = nil)
      # 1) First, try to match subject line patterns (custom campaigns, welcomes, etc.)
      if subject.present?
        CATEGORIES.each do |category, patterns|
          patterns.each do |pattern|
            return category.to_s if subject.match?(pattern)
          end
        end
      end

      # 2) If no subject match, use Lofty's emailType (but skip 'unknown' and event types)
      if lofty_email_type.present? && lofty_email_type != 'unknown'
        # Skip if it's actually an event type, not an email type (bad data)
        return nil if lofty_email_type.in?(['email_opened', 'email_sent', 'unsub', 'manual_unsub'])
        
        # Normalize a few Lofty types to friendlier names
        normalized = {
          'listing_alert' => 'property_alert',
          'market_report' => 'market_report',
          'seller_report' => 'seller_report',
          'home_report' => 'home_report',
          'smart_plan' => 'smart_plan'
        }[lofty_email_type]
        
        # Only return if we have a normalized mapping, otherwise return nil
        return normalized if normalized.present?
      end
      
      # 3) If neither matched, return nil (will be uncategorized)
      nil
    end

    def self.categories
      CATEGORIES.keys.map(&:to_s)
    end
    
    def self.category_name(category)
      {
        'event_mass_email' => 'Event Mass Email',
        'home_anniversary' => 'Home Anniversary',
        'monthly_newsletter' => 'Monthly Newsletter',
        'seller_welcome' => 'Seller Welcome',
        'buyer_welcome' => 'Buyer Welcome',
        'gre_intro' => 'GRE Intro',
        'holiday' => 'Holiday',
        'broker_open' => 'Broker Open',
        'open_house_invite' => 'Open House Invite',
        'rh_intro' => 'RH Intro',
        'manual_unsub' => 'Manual Unsub',
        'informational' => 'Informational',
        'listing_blast' => 'Listing Blast',
        'market_snapshot' => 'Market Snapshot'
      }[category] || category&.titleize
    end
  end
end
