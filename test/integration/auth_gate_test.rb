require "test_helper"

# Engine auth smoke: the landing page is public, sign-in is passwordless magic
# link only, and the magic link actually signs a player in.
class AuthGateTest < ActionDispatch::IntegrationTest
  # Controllers that deliberately skip require_authentication. Adding one is a
  # product decision, not a convenience — say why in the controller.
  PUBLIC_CONTROLLERS = %w[PagesController].freeze

  test "landing renders publicly and offers sign-in" do
    get root_path

    assert_response :success
    assert_select "h1", text: "Cyvasse"
    assert_select "a[href=?]", signin_path
  end

  test "the sign-in page offers magic link and nothing else" do
    get signin_path

    assert_response :success
    assert_select "form[action=?][method=post]", magic_link_request_path
    assert_select "input[type=password]", false, "no password field: this app has no password auth"
    assert_select "form[action=?]", "/auth/google_oauth2", false, "no Google button: :google is not enabled"
  end

  test "legacy /signup lands on /signin" do
    get "/signup"

    assert_redirected_to "/signin"
  end

  test "requesting a magic link records the sign-in email in the outbox" do
    assert Studio::EmailDelivery.available?, "studio_email_deliveries must exist, or mail silently bypasses the outbox"

    assert_difference -> { Studio::Link.count }, 1 do
      post magic_link_request_path, params: { email: "carl@example.com" }
    end
    assert_response :redirect
  end

  test "consuming a magic link signs the player in" do
    user = User.create!(email: "carl@example.com", name: "Carl Test")

    log_in_as(user)
    get root_path

    assert_response :success
    assert_select "p", text: /Signed in as Carl Test/
  end

  test "a magic link is single-use" do
    user = User.create!(email: "carl@example.com", name: "Carl Test")
    token = Studio::Link.create_magic_link(email: user.email).token

    post link_consume_path(token: token)
    get logout_path
    post link_consume_path(token: token)
    get root_path

    refute_match(/Signed in as/, response.body, "a burned token must not sign anyone in twice")
  end

  test "hub SSO routes are drawn" do
    assert_equal "/sso_login", sso_login_path
    assert_equal "/sso_continue", sso_continue_path
  end

  test "POST /sso_continue without a hub session falls back to sign-in" do
    post sso_continue_path

    assert_redirected_to login_path
  end

  test "wallet sign-in is not drawn: Cyvasse is web2" do
    refute Rails.application.routes.named_routes.key?(:auth_solana_nonce)
    assert_raises(ActionController::RoutingError) { Rails.application.routes.recognize_path("/auth/solana/nonce") }
  end

  # Positive invariant: every controller this app defines carries
  # require_authentication in its live callback chain unless it is allowlisted
  # public, where the ABSENCE is pinned instead. Engine controllers live in the
  # gem and are filtered out by source location.
  test "every app controller requires authentication unless allowlisted public" do
    Rails.application.eager_load!
    app_dir = Rails.root.join("app/controllers").to_s
    app_controllers = ApplicationController.descendants.select do |controller|
      path, _line = Object.const_source_location(controller.name)
      path.to_s.start_with?(app_dir)
    end
    assert_operator app_controllers.size, :>=, 1, "expected the app's controllers to load"

    app_controllers.each do |controller|
      filters = controller._process_action_callbacks.select { |cb| cb.kind == :before }.map(&:filter)
      if PUBLIC_CONTROLLERS.include?(controller.name)
        refute_includes filters, :require_authentication, "#{controller.name} is allowlisted public"
      else
        assert_includes filters, :require_authentication, "#{controller.name} must require authentication"
      end
    end
  end
end
