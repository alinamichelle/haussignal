Rails.application.routes.draw do
  # Health endpoint
  get "up" => "rails/health#show", as: :rails_health_check

  # Debug UI for inspecting events
  namespace :debug do
    resources :leads, only: [:index, :show]
  end

  # API v1
  namespace :api do
    namespace :v1 do
      
      # NEW: Login endpoint (Next.js will call this)
      resource :session, only: [:create]

      # (Existing) Auth endpoints
      post 'auth/login', to: 'auth#login'
      get 'auth/me', to: 'auth#me'

      # Unsubscribe endpoints
      get 'unsubs/summary', to: 'unsubs#summary'
      get 'unsubs/series', to: 'unsubs#series'
      get 'unsubs/campaigns', to: 'unsubs#campaigns'
      get 'unsubs/campaigns/:id', to: 'unsubs#campaign'
      get 'unsubs/leads', to: 'unsubs#leads'
      get 'unsubs/analytics', to: 'unsubs#analytics'

      # Leads endpoints
      get 'leads', to: 'leads#index'
      get 'leads/:id/unsub_details', to: 'leads#unsub_details'
      get 'leads/:id/profile', to: 'leads#profile'

      # Analytics endpoints
      get 'analytics/overview', to: 'analytics#overview'

    end
  end
end
