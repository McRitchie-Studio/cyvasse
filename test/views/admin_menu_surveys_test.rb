require "test_helper"

# [component] The admin menu (Studio.sidebar_sections' Admin group) links the
# engine's survey results at /admin/surveys; a player's menu does not.
class AdminMenuSurveysTest < ActionDispatch::IntegrationTest
  include LiveResults

  test "an admin's menu links Surveys; a player's does not" do
    log_in_as(player("warden", role: "admin"))
    get "/rules"
    assert_select "a[href='/admin/surveys']", text: /Surveys/

    reset!
    log_in_as(player("arya"))
    get "/rules"
    assert_select "a[href='/admin/surveys']", count: 0
  end
end
