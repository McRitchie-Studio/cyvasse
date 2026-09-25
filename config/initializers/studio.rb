# studio-engine wiring (studio-engine/docs/NEW_APP_SETUP.md section 4).
Studio.configure do |config|
  config.app_name = "Cyvasse"
  config.session_key = :cyvasse_user_id
  config.welcome_message = ->(user) { "Welcome to Cyvasse, #{user.display_name}!" }
  # Passwordless magic link only, and the line stays EXPLICIT: the engine's
  # default auth_methods includes :google, which would draw OAuth routes this
  # app has no client id for. Add :google (plus the omniauth gems and
  # initializer) as a deliberate feature task; never :wallet, which is the web3
  # bolt-on and Cyvasse signs no transactions.
  config.auth_methods = %i[magic_link]
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
  config.sidebar_sections = [
    { title: "Cyvasse", links: [
      { label: "Home", href: "/", emoji: "♟️", desc: "The front door" },
      { label: "Pieces", href: "/pieces", emoji: "🐘", desc: "Both piece skins" },
      { label: "Rules", href: "/rules", emoji: "📜", desc: "How to play" },
      { label: "About", href: "/about", emoji: "🐉", desc: "Where Cyvasse came from" }
    ] },
    { title: "Admin", admin: true, links: [
      { label: "Theme", href: "/admin/theme", emoji: "🎨", desc: "Palette + dark mode" },
      { label: "Error logs", href: "/error_logs", emoji: "🚨", desc: "Captured errors" }
    ] }
  ]
end
