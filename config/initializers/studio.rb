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
  # No logos yet: the title art arrives with the asset import (epic piece 3).
  # With none declared the engine navbar renders the app name alone.
  config.theme_logos = []
  # Placeholder brand colour (parchment gold) until piece 3 brings the original
  # art; /admin/theme can override it at runtime.
  config.theme_primary = "#C08A2E"
  config.sidebar_sections = [
    { title: "Cyvasse", links: [
      { label: "Home", href: "/", emoji: "♟️", desc: "The front door" }
    ] },
    { title: "Admin", admin: true, links: [
      { label: "Theme", href: "/admin/theme", emoji: "🎨", desc: "Palette + dark mode" },
      { label: "Error logs", href: "/error_logs", emoji: "🚨", desc: "Captured errors" }
    ] }
  ]
end
