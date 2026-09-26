require "test_helper"

# [unit] The hub SSO switch (config/initializers/session_store.rb). The shared
# cookie must be opt-in and production-only: flipping the hub's key and domain
# without the hub's SECRET_KEY_BASE would sign players out of the hub.
class SessionCookieTest < ActiveSupport::TestCase
  test "production defaults to Cyvasse's own host-scoped cookie" do
    options = CyvasseSessionCookie.options(production: true, env: {})

    assert_equal "_cyvasse_session", options[:key]
    assert_nil options[:domain], "no domain means the cookie stays on the request host"
    assert options[:secure]
    assert options[:httponly]
    assert_equal :lax, options[:same_site]
  end

  test "production joins the hub's cookie only when the flag is set" do
    options = CyvasseSessionCookie.options(production: true, env: { "STUDIO_SSO_SHARED_COOKIE" => "true" })

    assert_equal "_studio_session", options[:key]
    assert_equal ".mcritchie.studio", options[:domain]
    assert options[:secure]
  end

  test "anything but true leaves the shared cookie off" do
    %w[false 1 yes].push("").each do |value|
      options = CyvasseSessionCookie.options(production: true, env: { "STUDIO_SSO_SHARED_COOKIE" => value })

      assert_equal "_cyvasse_session", options[:key], "#{value.inspect} must not arm the shared cookie"
    end
  end

  test "the flag never shares the cookie off production" do
    options = CyvasseSessionCookie.options(production: false, env: { "STUDIO_SSO_SHARED_COOKIE" => "true" })

    assert_equal "_cyvasse_session", options[:key]
    assert_nil options[:domain]
    refute options[:secure]
  end

  test "a developer desk can rename its cookie" do
    options = CyvasseSessionCookie.options(production: false, env: { "CYVASSE_SESSION_KEY" => "_cyvasse_session_3601" })

    assert_equal "_cyvasse_session_3601", options[:key]
  end

  test "the booted app uses the helper's answer" do
    assert_equal "_cyvasse_session", Rails.application.config.session_options[:key]
    assert_equal :lax, Rails.application.config.session_options[:same_site]
  end
end
