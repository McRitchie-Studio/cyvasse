# 301s a request on any host but the canonical one (Cyvasse::CanonicalHost) to
# the same path and query on it: the old cyvasse.mcritchie.studio, the
# herokuapp.com host, anything else that reaches the dyno. Every "Cyvasse is
# back" email links to the old host with a ?ref= delivery token, so the query
# rides along whole.
#
# Exempt, and served on whatever host they arrive on:
#   - anything but GET and HEAD: a redirected POST, PATCH or DELETE loses its
#     body or becomes a GET, so a form or a webhook would silently fail
#   - /up: deploy gates and the release smoke probe the herokuapp host, and a
#     redirect there reads as healthy from the wrong page
#     (test/integration/health_endpoint_test.rb)
#   - /api/: the bot runner's bearer-token JSON (Api::Bot); an HTTP client
#     drops the Authorization header on a cross-host redirect
#   - /cable: a websocket upgrade does not follow redirects
#
# With no canonical host (a desk, a test) it passes everything through.
module Cyvasse
  class CanonicalHostRedirect
    REDIRECTED_METHODS = %w[GET HEAD].freeze
    EXEMPT_PATHS = %w[/up].freeze
    EXEMPT_PREFIXES = %w[/api/ /cable].freeze

    def initialize(app, host: -> { Cyvasse.canonical_host })
      @app = app
      @host = host
    end

    def call(env)
      host = @host.call
      request = Rack::Request.new(env)
      return @app.call(env) if host.nil? || canonical?(request, host) || exempt?(request)

      location = "#{CanonicalHost::PROTOCOL}://#{host}#{request.fullpath}"
      [ 301, { "location" => location, "content-type" => "text/plain", "cache-control" => "public, max-age=86400" },
        [ request.head? ? "" : "Moved to #{location}" ] ]
    end

    private

    def canonical?(request, host)
      request.host.to_s.downcase.delete_suffix(".") == host
    end

    def exempt?(request)
      return true unless REDIRECTED_METHODS.include?(request.request_method)

      path = request.path_info
      EXEMPT_PATHS.include?(path) || EXEMPT_PREFIXES.any? { |prefix| path == prefix.chomp("/") || path.start_with?(prefix) }
    end
  end
end
