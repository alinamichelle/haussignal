Rails.application.routes.draw do
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Defines the root path route ("/")
  # root "posts#index"
  
  # Debug UI for inspecting events
  namespace :debug do
    resources :leads, only: [:index, :show]
  end

  # API v1 - Unsubscribe Intelligence Dashboard
  namespace :api do
    namespace :v1 do
      # Auth endpoints
      post 'auth/login', to: 'auth#login'
      get 'auth/me', to: 'auth#me'
      
      # Unsub endpoints
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
