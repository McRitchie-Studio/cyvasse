require "test_helper"

# [unit] The one public host (lib/cyvasse/canonical_host.rb): in production the
# old host until CANONICAL_REDIRECT=1, then the bare cyvasse.xyz unless
# CANONICAL_HOST says otherwise; nothing at all on a desk or in a test unless
# CANONICAL_HOST is set, so the request host stands.
class CanonicalHostTest < ActiveSupport::TestCase
  ON = { "CANONICAL_REDIRECT" => "1" }.freeze

  test "production before the flip keeps the old host and redirects nothing" do
    assert_equal "cyvasse.mcritchie.studio", Cyvasse::CanonicalHost.host(env: {}, production: true)
    assert_nil Cyvasse::CanonicalHost.redirect_host(env: {}, production: true)
    refute Cyvasse::CanonicalHost.enforced?(env: { "CANONICAL_HOST" => "cyvasse.xyz" }, production: true),
           "CANONICAL_HOST alone must not start the move in production"
  end

  test "production before the flip still honours APP_HOST, as it did before the move" do
    assert_equal "qa.example.com", Cyvasse::CanonicalHost.host(env: { "APP_HOST" => "QA.example.com" }, production: true)
  end

  test "only CANONICAL_REDIRECT=1 turns the move on" do
    %w[0 true yes].each do |value|
      assert_nil Cyvasse::CanonicalHost.redirect_host(env: { "CANONICAL_REDIRECT" => value }, production: true), value
    end
  end

  test "production after the flip defaults to cyvasse.xyz, for links and the redirect" do
    assert_equal "cyvasse.xyz", Cyvasse::CanonicalHost.host(env: ON, production: true)
    assert_equal "cyvasse.xyz", Cyvasse::CanonicalHost.redirect_host(env: ON.merge("APP_HOST" => "old.example.com"), production: true)
  end

  test "CANONICAL_HOST overrides the default, trimmed and lowercased" do
    assert_equal "www.cyvasse.xyz",
                 Cyvasse::CanonicalHost.redirect_host(env: ON.merge("CANONICAL_HOST" => " WWW.Cyvasse.xyz "), production: true)
  end

  test "a blank CANONICAL_HOST falls back to the default in production" do
    assert_equal "cyvasse.xyz", Cyvasse::CanonicalHost.host(env: ON.merge("CANONICAL_HOST" => "  "), production: true)
  end

  test "outside production there is no canonical host unless one is set" do
    assert_nil Cyvasse::CanonicalHost.host(env: {}, production: false)
    assert_nil Cyvasse::CanonicalHost.redirect_host(env: {}, production: false)
    assert_equal "localhost", Cyvasse::CanonicalHost.host(env: { "CANONICAL_HOST" => "localhost" }, production: false)
    assert_equal "localhost", Cyvasse::CanonicalHost.redirect_host(env: { "CANONICAL_HOST" => "localhost" }, production: false)
  end

  test "url options are https on the host, or nil with no host" do
    assert_equal({ host: "cyvasse.xyz", protocol: "https" }, Cyvasse::CanonicalHost.url_options(host: "cyvasse.xyz"))
    assert_nil Cyvasse::CanonicalHost.url_options(host: nil)
  end

  test "url builds an absolute https URL for a path" do
    assert_equal "https://cyvasse.xyz/", Cyvasse::CanonicalHost.url(host: "cyvasse.xyz")
    assert_equal "https://cyvasse.xyz/rules", Cyvasse::CanonicalHost.url("/rules", host: "cyvasse.xyz")
    assert_equal "https://cyvasse.xyz/rules", Cyvasse::CanonicalHost.url("rules", host: "cyvasse.xyz")
    assert_nil Cyvasse::CanonicalHost.url("/rules", host: nil)
  end

  test "the Cyvasse shortcuts read the environment of this process" do
    assert_nil Cyvasse.canonical_host, "the test environment enforces no host"
    with_canonical_host("cyvasse.xyz") do
      assert_equal "cyvasse.xyz", Cyvasse.canonical_host
      assert_equal "https://cyvasse.xyz/play", Cyvasse.canonical_url("/play")
    end
  end

  test "the production config builds routes and mail on the canonical host" do
    production = Rails.root.join("config/environments/production.rb").read

    assert_includes production, "config.action_mailer.default_url_options = Cyvasse::CanonicalHost.url_options"
    assert_includes production, "Rails.application.routes.default_url_options = Cyvasse::CanonicalHost.url_options"
    refute_match(/ENV\S*APP_HOST/, production, "hosts are read only in lib/cyvasse/canonical_host.rb; a second read would drift from the redirect")
  end

  private

  def with_canonical_host(host)
    previous = ENV["CANONICAL_HOST"]
    ENV["CANONICAL_HOST"] = host
    yield
  ensure
    ENV["CANONICAL_HOST"] = previous
  end
end
