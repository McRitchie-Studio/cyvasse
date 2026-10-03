# studio-engine wiring (studio-engine/docs/NEW_APP_SETUP.md section 4).
Studio.configure do |config|
  config.app_name = "Cyvasse"
  # ---- Site identity + link preview (studio-engine docs/LINK_PREVIEW.md) ----
  # The DRAFTED title and description, the home page's own SEO copy
  # (SeoPage :home; test/models/link_preview_draft_test.rb keeps them equal).
  # The operator edits them at /admin/link_preview, a saved value wins, and
  # Studio.site_identity reads the result. Every page unfurls with this unless
  # it overrides it: the public pages pass their own words through
  # link_preview in layouts/_seo. The engine's head writes the og:/twitter:
  # tags (link_preview_tags :auto), so no template here writes its own.
  config.site_title = "Cyvasse: Play the Game of Thrones Board Game Online"
  config.site_description = "Play Cyvasse, the hex-board strategy game from A Song of Ice and Fire, " \
                            "free in your browser: live matchmaking, a computer opponent, no download."
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
  # ---- Site footer (studio-engine docs/SITE_FOOTER.md) ----
  # The engine's footer, rendered by `studio_site_footer` at the end of the
  # application layout (task cyvasse-footer-and-legal). The operator's standard
  # for every app (2026-10-03): the brand, a tagline from the app's own copy, the
  # app's own links, a contact email and the legal links. NO address, NO map, NO
  # phone and no booking scheduler, so the engine never requests Leaflet or a
  # map tile and the app needs no content-security-policy source (it enforces no
  # policy: config/initializers/content_security_policy.rb is the scaffold's,
  # commented out). No social row: Cyvasse shows no profile handles.
  #
  # The © line prints "© <year> <name>", and `name` is also the home link's
  # accessible name, so it says both the game and the operator.
  # test/integration/site_footer_test.rb pins every link below.
  config.site_footer = ->(view) {
    {
      name: "Cyvasse by McRitchie Studio LLC",
      wordmark: %w[Cyvasse],
      # The elephant the app already serves as its touch icon (layouts/_seo),
      # 22KB. The navbar has no logo (theme_logos is empty), so the engine
      # would otherwise draw none.
      logo: "/icon.png",
      home_path: view.root_path,
      # The home page's own description (SeoPage :home), cut to one line.
      tagline: "The hex-board strategy game from A Song of Ice and Fire, free in your browser.",
      # The address every Cyvasse email is sent from (mailer_from above).
      email: "team@mcritchie.studio",
      columns: [
        [ "Play", [ [ "Play the computer", view.play_path ],
                    [ "Cyvasse Night", view.night_path ],
                    [ "Leaderboard", view.leaderboard_path ] ] ],
        [ "Learn", [ [ "Rules", view.rules_path ],
                     [ "Pieces", view.pieces_path ],
                     [ "About", view.about_path ] ] ],
        [ "Legal", [ [ "Privacy Policy", view.privacy_path ],
                     [ "Terms of Service", view.terms_path ] ] ]
      ],
      legal: [ [ "Privacy Policy", view.privacy_path ], [ "Terms of Service", view.terms_path ] ]
    }
  }

  # WHERE IT SHOWS. A visitor sees it on every public page; a signed-in player
  # (a Play Now guest included) only on the reading pages below. Never on a
  # game board, signed in or out: /play (games), a match and Play Now's search
  # (live_seeks) keep the whole screen for the board, and the onboarding and
  # the Chat hub are working surfaces. The engine's default rule, narrowed.
  config.site_footer_controllers = %w[pages legal leaderboards nights]
  config.site_footer_visible = ->(view) {
    Studio::SiteFooter.default_visible?(view) &&
      %w[games matches live_seeks onboarding conversations].exclude?(view.controller_name)
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
      { label: "Link preview", href: "/admin/link_preview", emoji: "🔗", desc: "The card a shared link unfurls into" },
      { label: "Error logs", href: "/error_logs", emoji: "🚨", desc: "Captured errors" }
    ] }
  ]
end
