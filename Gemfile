source "https://rubygems.org"

# Bundle edge Rails instead: gem "rails", github: "rails/rails", branch: "main"
gem "rails", "~> 8.1.3"
# The modern asset pipeline for Rails [https://github.com/rails/propshaft]
gem "propshaft"
# Use postgresql as the database for Active Record
gem "pg", "~> 1.1"
# Use the Puma web server [https://github.com/puma/puma]
gem "puma", ">= 5.0"
# Use JavaScript with ESM import maps [https://github.com/rails/importmap-rails]
gem "importmap-rails"
# Hotwire's SPA-like page accelerator [https://turbo.hotwired.dev]
gem "turbo-rails"
# Hotwire's modest JavaScript framework [https://stimulus.hotwired.dev]
gem "stimulus-rails"
# json 3.0 drops JSON.parse's two-argument form, which ActiveSupport 8.1.3.1
# still calls (active_support/json/decoding.rb:25): under it every JSON column
# fails to dump into db/schema.rb and every decode raises ArgumentError. The hub
# and turf-monster resolve 2.x because their locks predate 3.0; an unpinned
# fresh app resolves 3.0. Lift this with the Rails bump that supports json 3.
gem "json", "~> 2.20"
# Use Tailwind CSS [https://github.com/rails/tailwindcss-rails]
gem "tailwindcss-rails", "~> 4.5"

# Shared McRitchie Studio engine: passwordless auth, hub SSO awareness, theme,
# ErrorLog / rescue_and_log, local email capture, local review. The pin is a
# FLOOR (a two-segment ~> admits every 0.x): 0.84 (task
# cyvasse-engine-bump-and-pool) carries 0.81's warning/danger button contrast
# and single admin cog on phones, the `redis < 6` gemspec cap (0.82.1), and the
# site footer's fixed-row grid that keeps the contact email on one line (0.84.0;
# task cyvasse-footer-and-legal).
# Older floors: 0.78 for Studio.navbar_links (task cyvasse-nav-links), 0.57 for
# Studio::GeoDetection. Read Gemfile.lock for what actually resolves.
gem "studio-engine", "~> 0.88"
# Google sign-in through the engine's OmniauthCallbacksController, beside the
# magic link (config/initializers/omniauth.rb). The same three gems the hub runs.
# ES256 assertions from the hub (EmailHandoff::Verifier).
gem "jwt", "~> 3.1"
gem "omniauth"
gem "omniauth-google-oauth2"
gem "omniauth-rails_csrf_protection"
# Pin redis below 6 for ActionCable's redis pubsub adapter (config/cable.yml,
# production). studio-engine before 0.82.1 declared `redis >= 4.0.1` with NO
# upper bound (0.82.1 and later cap it `< 6`; this pin stays as Cyvasse's own
# guard regardless of the engine), so bundler resolved redis 6.0.0 — but
# ActionCable 8.1's redis adapter declares `gem "redis", ">= 4", "< 6"`, and
# in production ActionCable.server.pubsub raised "can't activate redis (>= 4, < 6), already activated redis-6.0.0":
# /cable still upgraded (101) but no broadcast reached a subscriber, so live
# chat never updated. The hub hit the same float and pins it the same way
# (mcritchie-studio Gemfile). test/lib/redis_cable_adapter_test.rb guards it.
#
# Lift it deliberately, in its own task, once Rails' adapter accepts redis 6.
gem "redis", "~> 5.4"

# Use Active Model has_secure_password [https://guides.rubyonrails.org/active_model_basics.html#securepassword]
# gem "bcrypt", "~> 3.1.7"

# Windows does not include zoneinfo files, so bundle the tzinfo-data gem
gem "tzinfo-data", platforms: %i[ windows jruby ]

# Reduces boot times through caching; required in config/boot.rb
gem "bootsnap", require: false

# Add HTTP asset caching/compression and X-Sendfile acceleration to Puma [https://github.com/basecamp/thruster/]
gem "thruster", require: false

# Use Active Storage variants [https://guides.rubyonrails.org/active_storage_overview.html#transforming-images]
gem "image_processing", "~> 1.2"

group :development, :test do
  # See https://guides.rubyonrails.org/debugging_rails_applications.html#debugging-with-the-debug-gem
  gem "debug", platforms: %i[ mri windows ], require: "debug/prelude"

  # Audits gems for known security defects (use config/bundler-audit.yml to ignore issues)
  gem "bundler-audit", require: false

  # Static analysis for security vulnerabilities [https://brakemanscanner.org/]
  gem "brakeman", require: false

  # Omakase Ruby styling [https://github.com/rails/rubocop-rails-omakase/]
  gem "rubocop-rails-omakase", require: false
end

group :development do
  # Use console on exceptions pages [https://github.com/rails/web-console]
  gem "web-console"
end

# Load .env in development/test (engine + app config)
gem "dotenv-rails", groups: [ :development, :test ]

group :test do
  # Use system testing [https://guides.rubyonrails.org/testing.html#system-testing]
  gem "capybara"
  gem "selenium-webdriver"
end
