# The one public host Cyvasse lives on, and the one place that says so.
#
# Cyvasse moved from cyvasse.mcritchie.studio to its own domain, cyvasse.xyz
# (task cyvasse-canonical-domain). Heroku serves https://www.cyvasse.xyz; the
# bare cyvasse.xyz forwards to it at the registrar. Everything that builds an
# absolute URL reads the host from here: the routes' and mailers'
# default_url_options (config/environments/production.rb, ApplicationMailer),
# and Cyvasse::CanonicalHostRedirect, which 301s every other host here.
# Later work (canonical tags, a sitemap, Open Graph image URLs) builds on
# Cyvasse.canonical_host and Cyvasse.canonical_url rather than a new constant.
#
#   production   CANONICAL_HOST, else "www.cyvasse.xyz"
#   elsewhere    CANONICAL_HOST, else nil: a desk or a test keeps the request
#                host, and nothing redirects
#
# The scheme is always https: a canonical host is a public TLS host.
#
# This file sits outside the autoloader (config/application.rb requires it and
# ignores lib/cyvasse), because config/environments/production.rb reads it
# before autoloading is set up.
module Cyvasse
  module CanonicalHost
    DEFAULT = "www.cyvasse.xyz".freeze
    PROTOCOL = "https".freeze

    # The host alone ("www.cyvasse.xyz"), or nil where none is enforced.
    def self.host(env: ENV, production: Rails.env.production?)
      configured = env["CANONICAL_HOST"].to_s.strip.downcase.presence
      configured || (DEFAULT if production)
    end

    # { host:, protocol: } for default_url_options, or nil where none is set.
    def self.url_options(host: self.host)
      { host: host, protocol: PROTOCOL } if host
    end

    # An absolute URL for `path` on the canonical host, or nil where none is set.
    def self.url(path = "/", host: self.host)
      return unless host

      path = "/#{path}" unless path.start_with?("/")
      "#{PROTOCOL}://#{host}#{path}"
    end
  end

  def self.canonical_host
    CanonicalHost.host
  end

  def self.canonical_url(path = "/")
    CanonicalHost.url(path)
  end
end
