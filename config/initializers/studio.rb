# studio-engine wiring (studio-engine/docs/NEW_APP_SETUP.md section 4).
Studio.configure do |config|
  config.app_name = "Cyvasse"
  config.session_key = :cyvasse_user_id
  # Page changes present with the McRitchie Studio view transition
  # (layouts/studio/_smooth_load); Play Now's searching page and splash lean on it.
  config.smooth_load = true
  # A player's one public name everywhere (User#player_name).
  config.welcome_message = ->(user) { "Welcome to Cyvasse, #{user.player_name}!" }
  # The navbar shows that public name too ("Guest_4821"), not display_name,
  # which is a real name first and stays for email greetings and the admin
  # pages (task cyvasse-contrast-and-names). And every Cyvasse view says
  # "Sign in", so the engine navbar's signed-out button does as well
  # (test/views/sign_in_wording_test.rb). Both since studio-engine 0.80.0,
  # which is what let Cyvasse drop its copy of components/_user_nav.
  config.navbar_user_name = :player_name
  config.sign_in_label = "Sign in"
  # Magic link always; Google only where its OAuth client is configured
  # (CyvasseGoogleSignIn, config/initializers/omniauth.rb). Never :wallet, the
  # web3 bolt-on: Cyvasse signs no transactions.
  config.auth_methods = CyvasseGoogleSignIn.enabled? ? %i[magic_link google] : %i[magic_link]
  config.registration_params = [ :name, :email ]
  config.mailer_from = Studio.mailer_from_for_transport(
    ses_from: "Cyvasse <team@mcritchie.studio>"
  )
  # A player who arrives signed in through the hub's SSO is an ordinary member.
  config.configure_sso_user = ->(user) { user.role = "viewer" }
  # No logos yet. The title art (app/assets/images/title/) is a wide wordmark
  # and the navbar logo slot is a round badge, so it is not wired here. With
  # none declared the engine navbar renders the app name alone.
  config.theme_logos = []
  # Placeholder brand colour (parchment gold). The original art is in the app
  # now (piece 3), but a palette drawn from it is a product call left open;
  # /admin/theme can override it at runtime.
  config.theme_primary = "#C08A2E"
  # The success green, which fills btn-secondary under a white label. The
  # engine's #4BAF50 is 2.78:1 under white, below WCAG AA's 4.5:1; this is the
  # same green 28% deeper, 5.0:1 (task cyvasse-contrast-and-names). The gold
  # needs two shades, a deep fill under white and a light-or-deep ink by theme,
  # which one hex cannot say: app/assets/tailwind/application.css picks them
  # from the engine's primary scale.
  config.theme_success = "#367E3A"
  # The navbar's own links, My games and Leaderboard with the player's live
  # rank (NavbarLinks; task cyvasse-nav-links).
  config.navbar_links = ->(view) { NavbarLinks.call(view) }
  # /profile and /profile/edit (the engine's page) lead with the public
  # username (task cyvasse-profile-username-edit): a row on the read page, and
  # a card above Name on the edit page with its own Save (profiles/_username).
  # The engine's rows follow unchanged. A lambda, so each request composes
  # against a fresh copy of the defaults.
  config.profile_sections = lambda { |_view|
    [
      { key: :username, title: "Username", page: :show, partial: "profiles/username_summary", requires: :username },
      { key: :username, title: "Username", page: :edit, partial: "profiles/username", requires: :username }
    ] + Studio.default_profile_sections
  }
  config.sidebar_sections = [
    { title: "Cyvasse", links: [
      { label: "Home", href: "/", emoji: "♟️", desc: "The front door" },
      { label: "Play", href: "/play", emoji: "🐲", desc: "A game against the computer" },
      { label: "My games", href: "/matches", emoji: "⚔️", desc: "Online matches against players" },
      { label: "Leaderboard", href: "/leaderboard", emoji: "🏆", desc: "Who is winning live games" },
      { label: "Chat", href: "/conversations", emoji: "💬", desc: "Talk with players you have played" },
      { label: "Pieces", href: "/pieces", emoji: "🐘", desc: "Both piece skins" },
      { label: "Rules", href: "/rules", emoji: "📜", desc: "How to play" },
      { label: "About", href: "/about", emoji: "🐉", desc: "Where Cyvasse came from" }
    ] },
    { title: "Admin", admin: true, links: [
      { label: "Conversations", href: "/admin/conversations", emoji: "💬", desc: "Every conversation between players" },
      { label: "Message Board", href: "/admin/message_board", emoji: "📌", desc: "The old public message board" },
      { label: "Sign-ins", href: "/admin/sign_ins", emoji: "🔑", desc: "Email sign-ins and onboarding drop-off" },
      { label: "Theme", href: "/admin/theme", emoji: "🎨", desc: "Palette + dark mode" },
      { label: "Error logs", href: "/error_logs", emoji: "🚨", desc: "Captured errors" }
    ] }
  ]
end
