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

# The canonical host, read by config/environments/production.rb before the
# autoloader runs, and the middleware that redirects to it
# (lib/cyvasse/canonical_host.rb).
require_relative "../lib/cyvasse/canonical_host"
require_relative "../lib/cyvasse/canonical_host_redirect"
# The database connection budget: Puma threads, ActionCable workers, and the
# pool that covers both (lib/cyvasse/connection_budget.rb).
require_relative "../lib/cyvasse/connection_budget"

module Cyvasse
  class Application < Rails::Application
    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 8.1

    # Please, add to the `ignore` list any other `lib` subdirectories that do
    # not contain `.rb` files, or that should not be reloaded or eager loaded.
    # Common ones are `templates`, `generators`, or `middleware`, for example.
    config.autoload_lib(ignore: %w[assets tasks cyvasse])

    # ActionCable's worker pool runs channel callbacks (live chat), each on a
    # database connection. Set explicitly, from the same budget that sizes the
    # pool in config/database.yml, rather than left to Rails' default of 4.
    config.action_cable.worker_pool_size = Cyvasse::ConnectionBudget.cable_workers

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
    # One public host: every other host a GET arrives on 301s to
    # Cyvasse.canonical_host, path and query intact. First in the stack, so an
    # http:// request on the old host takes one hop, not two (after
    # ActionDispatch::SSL). Inert where no canonical host is set.
    config.middleware.insert_before 0, Cyvasse::CanonicalHostRedirect

    config.middleware.insert_after Rack::Sendfile, Rack::Deflater, include: %w[
      text/html text/css text/javascript text/plain text/vnd.turbo-stream.html
      application/javascript application/json application/xml application/manifest+json
      image/svg+xml
    ]
  end
end
