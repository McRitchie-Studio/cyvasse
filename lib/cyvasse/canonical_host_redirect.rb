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
#   - any GET that is not a full-page navigation: a live match's state poll
#     and the seek poll fetch JSON from the page's own host, and a 301 to
#     another site fails CORS, which the poller reads as "offline" forever
#     while the clock runs. A page already open on the old host keeps working
#     there; its next navigation moves it. Sec-Fetch-Mode decides where the
#     browser sends it; without it, an XHR or a JSON-only Accept stays put.
#
# The host is compared from Host itself, never X-Forwarded-Host, which any
# client can set (Heroku's router sets Host from the request line).
#
# The 301 is cached privately for an hour, not a day: a flag flipped too
# early and backed out must not strand browsers on a dead host for long.
#
# With no redirect host (a desk, a test, or production before
# CANONICAL_REDIRECT=1) it passes everything through.
module Cyvasse
  class CanonicalHostRedirect
    REDIRECTED_METHODS = %w[GET HEAD].freeze
    EXEMPT_PATHS = %w[/up].freeze
    EXEMPT_PREFIXES = %w[/api/ /cable].freeze

    def initialize(app, host: -> { Cyvasse::CanonicalHost.redirect_host })
      @app = app
      @host = host
    end

    def call(env)
      host = @host.call
      request = Rack::Request.new(env)
      return @app.call(env) if host.nil? || canonical?(request, host) || exempt?(request)

      location = "#{CanonicalHost::PROTOCOL}://#{host}#{request.fullpath}"
      [ 301, { "location" => location, "content-type" => "text/plain", "cache-control" => "private, max-age=3600" },
        [ request.head? ? "" : "Moved to #{location}" ] ]
    end

    private

    def canonical?(request, host)
      request.get_header("HTTP_HOST").to_s.downcase.sub(/:\d+\z/, "").delete_suffix(".") == host
    end

    def exempt?(request)
      return true unless REDIRECTED_METHODS.include?(request.request_method)
      return true unless navigation?(request)

      path = request.path_info
      EXEMPT_PATHS.include?(path) || EXEMPT_PREFIXES.any? { |prefix| path == prefix.chomp("/") || path.start_with?(prefix) }
    end

    def navigation?(request)
      mode = request.get_header("HTTP_SEC_FETCH_MODE").to_s
      return mode == "navigate" unless mode.empty?
      return false if request.xhr?

      accept = request.get_header("HTTP_ACCEPT").to_s
      accept.empty? || accept.include?("text/html") || accept.include?("*/*")
    end
  end
end
