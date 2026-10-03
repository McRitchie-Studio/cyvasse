require "test_helper"

# [integration] Losing the username race (task cyvasse-username-unique-index):
# when another account takes the name in another case between the check and
# the write, the unique index refuses it, and every surface that sets a
# username (the /username page, the profile's Username card, onboarding)
# shows the normal "is taken", never a 500.
class UsernameRaceTest < ActionDispatch::IntegrationTest
  include LiveResults
  include UsernameRace

  setup do
    UsernamesController::RATE_STORE.clear
    @arya = player("arya")
    player("jon")
  end

  test "the /username page shows taken" do
    log_in_as(@arya)

    as_if_the_check_raced { patch username_path, params: { username: "JON" } }
    assert_response :unprocessable_entity
    assert_match "Username is taken", response.body
    assert_equal "arya", @arya.reload.username
  end

  test "the profile's Username card shows taken" do
    log_in_as(@arya)

    as_if_the_check_raced { patch username_path, params: { username: "Jon", from: "profile", return_to: edit_profile_path } }
    assert_redirected_to edit_profile_path(anchor: "username")
    follow_redirect!
    assert_select "#profile_username_error", "Username is taken."
    assert_equal "arya", @arya.reload.username
  end

  test "onboarding's username step shows taken" do
    rook = User.create!(email: "rook@example.com", name: "Rook", legacy_id: 11)
    rook.update_columns(username: "the rook!")
    log_in_as(rook)

    as_if_the_check_raced { patch onboarding_step_path("username"), params: { username: "jON" } }
    assert_response :unprocessable_entity
    assert_match "Username is taken", response.body
    assert_equal "the rook!", rook.reload.username
  end
end
