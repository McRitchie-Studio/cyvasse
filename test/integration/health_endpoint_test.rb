require "test_helper"

# /up is what every deploy gate and uptime monitor probes. It must answer 200
# signed out and WITHOUT a redirect: a probe bounced to the sign-in page still
# reads 200 from the wrong page and reports healthy.
class HealthEndpointTest < ActionDispatch::IntegrationTest
  test "GET /up answers 200 signed out" do
    get "/up"

    assert_response :success
  end

  test "the health endpoint never redirects" do
    get "/up"

    refute response.redirect?, "a redirect on /up is the bug: the probe would land on #{response.location.inspect}"
  end

  test "the routed health path is /up" do
    assert_equal "/up", rails_health_check_path
  end
end
