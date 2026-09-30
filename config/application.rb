require_relative "boot"

require "rails"
# Pick the frameworks you want:
require "active_model/railtie"
require "active_job/railtie"
require "active_record/railtie"
require "active_storage/engine"
require "action_controller/railtie"
require "action_mailer/railtie"
# require "action_mailbox/engine"
# require "action_text/engine"
require "action_view/railtie"
require "action_cable/engine"
require "rails/test_unit/railtie"

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

module Cyvasse
  class Application < Rails::Application
    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 8.1

    # Please, add to the `ignore` list any other `lib` subdirectories that do
    # not contain `.rb` files, or that should not be reloaded or eager loaded.
    # Common ones are `templates`, `generators`, or `middleware`, for example.
    config.autoload_lib(ignore: %w[assets tasks])

    # Configuration for the application, engines, and railties goes here.
    #
    # These settings can be overridden in specific environments using the files
    # in config/environments, which are processed later.
    #
    # config.time_zone = "Central Time (US & Canada)"
    # config.eager_load_paths << Rails.root.join("extras")

    # GZIP. Nothing in front of the app compresses (Heroku's router passes
    # bodies through), and Propshaft writes no .gz beside its digested assets,
    # so ActionDispatch::Static would serve them raw. Inserted after
    # Rack::Sendfile, it wraps Static and the app alike: pages, JSON, turbo
    # streams, and the JS and CSS assets. Only text types, so images and fonts
    # (already compressed) pass through. It skips on its own what must not be
    # touched: a response that already has a content-encoding, a 1xx/204/304
    # (the ActionCable upgrade is a 101), and Cache-Control: no-transform.
    # ETags are made inside it, over the uncompressed body, and its Vary:
    # Accept-Encoding keeps a shared cache from serving gzip to a client that
    # did not ask. sync (the default) flushes each chunk, so streaming stays live.
    config.middleware.insert_after Rack::Sendfile, Rack::Deflater, include: %w[
      text/html text/css text/javascript text/plain text/vnd.turbo-stream.html
      application/javascript application/json application/xml application/manifest+json
      image/svg+xml
    ]
  end
end
