module Lofty
  class EmailCategoryClassifier
    # Define email categories and their matching patterns
    CATEGORIES = {
      # Event mass emails
      event_mass_email: [
        /haus huddle/i,
        /haus for the holidays/i,
        /crawfish boil/i
      ],
      
      # Home anniversary smart plan
      home_anniversary: [
        /haus-iversary/i,
        /hausiversary/i
      ],
      
      # Monthly newsletter
      monthly_newsletter: [
        /austin'?s monthly digest/i
      ],
      
      # Seller welcome email
      seller_welcome: [
        /your haus,?\s*our commitment/i
      ],
      
      # Buyer welcome email
      buyer_welcome: [
        /haus hunting made easy/i
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

      # 2) If no subject match, use Lofty's emailType (but skip 'unknown')
      if lofty_email_type.present? && lofty_email_type != 'unknown'
        # Normalize a few Lofty types to friendlier names
        normalized = {
          'listing_alert' => 'property_alert',
          'market_report' => 'market_report',
          'seller_report' => 'seller_report',
          'home_report' => 'home_report',
          'smart_plan' => 'smart_plan'
        }[lofty_email_type] || lofty_email_type
        return normalized
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
        'buyer_welcome' => 'Buyer Welcome'
      }[category] || category&.titleize
    end
  end
end
