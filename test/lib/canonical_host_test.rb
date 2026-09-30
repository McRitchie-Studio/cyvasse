require "test_helper"

# [unit] The one public host (lib/cyvasse/canonical_host.rb): the bare cyvasse.xyz
# in production unless CANONICAL_HOST says otherwise, and nothing at all on a
# desk or in a test unless CANONICAL_HOST is set, so the request host stands.
class CanonicalHostTest < ActiveSupport::TestCase
  test "production defaults to cyvasse.xyz" do
    assert_equal "cyvasse.xyz", Cyvasse::CanonicalHost.host(env: {}, production: true)
  end

  test "CANONICAL_HOST overrides the default, trimmed and lowercased" do
    assert_equal "qa.cyvasse.xyz",
                 Cyvasse::CanonicalHost.host(env: { "CANONICAL_HOST" => " QA.Cyvasse.xyz " }, production: true)
  end

  test "a blank CANONICAL_HOST falls back to the default in production" do
    assert_equal "cyvasse.xyz", Cyvasse::CanonicalHost.host(env: { "CANONICAL_HOST" => "  " }, production: true)
  end

  test "outside production there is no canonical host unless one is set" do
    assert_nil Cyvasse::CanonicalHost.host(env: {}, production: false)
    assert_equal "localhost", Cyvasse::CanonicalHost.host(env: { "CANONICAL_HOST" => "localhost" }, production: false)
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
    refute_match(/ENV\S*APP_HOST/, production, "APP_HOST is retired; a second host setting would drift from the redirect")
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
