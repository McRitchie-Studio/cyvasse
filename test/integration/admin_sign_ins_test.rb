require "test_helper"

# [integration] /admin/sign_ins: email handoff sign-ins by outcome and reason,
# and the onboarding funnel. Admins only; anyone else gets a 404.
class AdminSignInsTest < ActionDispatch::IntegrationTest
  include LiveResults

  test "an admin sees handoff counts, reasons, last use and the onboarding funnel" do
    admin = player("warden", role: "admin")
    arya = player("arya")
    travel_to(Time.zone.parse("2026-09-28 10:00")) { EmailHandoffAttempt.record("signed_in", user: arya) }
    EmailHandoffAttempt.record("signed_in", user: arya)
    2.times { EmailHandoffAttempt.record("rejected", reason: :expired) }
    EmailHandoffAttempt.record("rejected", reason: :replayed)
    EmailHandoffAttempt.record("no_account")
    arya.record_onboarding!("welcome", "done")
    arya.record_onboarding!("username", "shown")

    log_in_as(admin)
    get admin_sign_ins_path
    assert_response :success
    assert_select "[data-handoff-totals]", /6 handoff attempts, 2 signed in/
    assert_select "[data-outcome=signed_in] [data-count]", "2"
    assert_select "[data-outcome=rejected][data-reason=expired] [data-count]", "2"
    assert_select "[data-outcome=rejected][data-reason=replayed] [data-count]", "1"
    assert_select "[data-outcome=no_account] [data-count]", "1"
    assert_select "[data-handoff-recent] li", 6
    assert_select "[data-onboarding-funnel] [data-step=welcome] [data-rate]", "100%"
    assert_select "[data-onboarding-funnel] [data-step=username] [data-stopped]", "1"
    assert_select "[data-onboarding-funnel] [data-step=contact] [data-rate]", "—"
  end

  test "a player gets a 404 and a visitor is sent to sign in" do
    log_in_as(player("arya"))
    get admin_sign_ins_path
    assert_response :not_found

    reset!
    get admin_sign_ins_path
    assert_redirected_to login_path
  end
end
