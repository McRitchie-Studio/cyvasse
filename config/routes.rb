Rails.application.routes.draw do
  # Health check: every deploy gate and uptime monitor probes it, so it stays
  # outside the auth gate and never redirects
  # (test/integration/health_endpoint_test.rb).
  get "up" => "rails/health#show", as: :rails_health_check

  # Canonical passwordless sign-in page; legacy GETs land on it.
  get "signin", to: "sessions#new", as: :signin
  get "signup", to: redirect("/signin"), as: nil

  # studio-engine: /login, magic link (POST /magic_link, /l/:token), /logout,
  # hub SSO (/sso_login, POST /sso_continue), /error_logs, /admin/theme, the
  # local email inbox and local review on developer desks.
  Studio.routes(self)

  # Both piece skins side by side (epic cyvasse-revival piece 3). Public, like
  # the landing page: it is art, not a game surface.
  get "pieces", to: "pages#pieces", as: :pieces

  root "pages#index"
end
