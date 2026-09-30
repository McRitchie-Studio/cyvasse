# The one public host Cyvasse lives on, and the one place that says so.
#
# Cyvasse moved from cyvasse.mcritchie.studio to its own domain, cyvasse.xyz
# (task cyvasse-canonical-domain). The bare domain is canonical: Heroku serves
# https://cyvasse.xyz (an ALIAS record at the apex), and www.cyvasse.xyz, like
# the old host, redirects to it. Everything that builds an
# absolute URL reads the host from here: the routes' and mailers'
# default_url_options (config/environments/production.rb, ApplicationMailer),
# and Cyvasse::CanonicalHostRedirect, which 301s every other host here.
# Later work (canonical tags, a sitemap, Open Graph image URLs) builds on
# Cyvasse.canonical_host and Cyvasse.canonical_url rather than a new constant.
#
# The move is GATED in production, because cyvasse.xyz may not resolve yet
# (its public DNS waited on a DNSSEC change at the registry). Until
# CANONICAL_REDIRECT=1 is set, production behaves exactly as it did before the
# move: links build on APP_HOST, else cyvasse.mcritchie.studio, and nothing
# redirects. Flip the flag only once https://<host>/up answers 200.
#
#   production, CANONICAL_REDIRECT=1   CANONICAL_HOST, else "cyvasse.xyz";
#                                      the redirect is on
#   production, flag unset             APP_HOST, else cyvasse.mcritchie.studio;
#                                      the redirect is off
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
    DEFAULT = "cyvasse.xyz".freeze
    LEGACY = "cyvasse.mcritchie.studio".freeze
    PROTOCOL = "https".freeze

    # Is the move on? In production only CANONICAL_REDIRECT=1 turns it on;
    # elsewhere a set CANONICAL_HOST is the opt-in.
    def self.enforced?(env: ENV, production: Rails.env.production?)
      return env["CANONICAL_REDIRECT"].to_s.strip == "1" if production

      configured(env).present?
    end

    # The host absolute URLs are built on ("cyvasse.xyz"), or nil where none is set.
    def self.host(env: ENV, production: Rails.env.production?)
      return configured(env) unless production
      return configured(env) || DEFAULT if enforced?(env: env, production: true)

      env["APP_HOST"].to_s.strip.downcase.presence || LEGACY
    end

    # The host Cyvasse::CanonicalHostRedirect sends other hosts to, or nil
    # while the move is off.
    def self.redirect_host(env: ENV, production: Rails.env.production?)
      host(env: env, production: production) if enforced?(env: env, production: production)
    end

    def self.configured(env)
      env["CANONICAL_HOST"].to_s.strip.downcase.presence
    end
    private_class_method :configured

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
