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
    # The match's chat (piece 12): its two players only.
    resources :messages, only: %i[index create], controller: "match_messages"
  end
  # A player's conversations, newest first, and each one's whole thread with
  # a reply box. A conversation is addressed by the other player's user id.
  get "inbox", to: "conversations#index", as: :inbox
  resources :conversations, only: :show do
    post :messages, on: :member, action: :reply, as: :reply
  end
  # Every conversation that ever happened, and the match each message was in,
  # and the old public message board (piece 15): admins only; anyone else
  # gets a 404.
  namespace :admin do
    resources :conversations, only: %i[index show]
    resources :matches, only: :show
    get "message_board", to: "message_board#index", as: :message_board
  end
  # Saved army lineups (piece 10b): save the army on the board to one of three
  # slots; the setup panel loads them in the browser.
  post "lineups", to: "setups#create", as: :setups
  # The public name a player is challenged by.
  get "username", to: "usernames#edit", as: :username
  patch "username", to: "usernames#update"

  root "pages#index"
end
