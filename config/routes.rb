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
  # The rulebook and the about page, ported from the original site (piece 7).
  get "rules", to: "pages#rules", as: :rules
  get "about", to: "pages#about", as: :about
  # A game against the computer, played in the browser (piece 4). Public: no
  # account and nothing saved until matches arrive (piece 6).
  get "play", to: "games#show", as: :play
  # The piece-skin switcher (piece 5): remembers pencil or vector in a cookie,
  # and on the account when signed in. Public, like the pages it serves.
  patch "skin", to: "skins#update", as: :skin

  # Online matches between signed-in players (piece 6): My Games, challenge by
  # username, setup, turns, resign. Players only; every move is checked on the
  # server by CyvasseRules (app/models/cyvasse_rules).
  resources :matches, only: %i[index show create destroy] do
    member do
      post :accept
      post :setup, action: :set_up
      post :moves, action: :move
      post :resign
    end
  end
  # The public name a player is challenged by.
  get "username", to: "usernames#edit", as: :username
  patch "username", to: "usernames#update"

  root "pages#index"
end
