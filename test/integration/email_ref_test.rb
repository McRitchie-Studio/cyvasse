require "test_helper"

# [integration] A player who arrives from an email (the hub's click redirect
# adds ?ref=<delivery token>) is credited to it: the page carries the beacon
# URL for the board, and the first full signed-in page draws the signed_in
# beacon exactly once. A redirect, a Turbo frame or a prefetch never uses up
# that one beacon, and a signed-out reader keeps the ref through sign-in.
class EmailRefTest < ActionDispatch::IntegrationTest
  REF = "AbCdEfGhIjKlMnOpQrSt12"

  setup do
    @arya = User.create!(email: "arya@example.com", name: "Arya", username: "arya")
  end

  def beacon_url(goal = nil, ref: REF)
    "#{EmailReferral.hub_url}/e/g/#{ref}?g=#{goal}"
  end

  test "outside production the beacons go to the local hub, never to production" do
    assert_equal "http://localhost:3000", EmailReferral.hub_url
  end

  test "a visitor with no ref gets no beacon and no meta tag" do
    get play_path
    assert_select "meta[name='email-goal-url']", count: 0
    assert_select "img[data-email-beacon]", count: 0
  end

  test "a ref is remembered and the board gets the hub's beacon URL" do
    get play_path(ref: REF)
    assert_select "meta[name='email-goal-url'][content=?]", beacon_url
    get rules_path
    assert_select "meta[name='email-goal-url'][content=?]", beacon_url
  end

  test "a malformed ref is ignored" do
    get play_path(ref: "<script>")
    assert_select "meta[name='email-goal-url']", count: 0
  end

  test "signing in draws the signed_in beacon on one page only" do
    get play_path(ref: REF)
    assert_select "img[data-email-beacon]", count: 0, message: "not signed in yet"

    log_in_as(@arya)
    get play_path
    assert_select "img[data-email-beacon][src=?]", beacon_url("signed_in")
    get play_path
    assert_select "img[data-email-beacon]", count: 0
  end

  test "a second email's ref counts its own sign-in" do
    log_in_as(@arya)
    get play_path(ref: REF)
    get play_path(ref: "ZyXwVuTsRqPoNmLkJiHg98")
    assert_select "img[data-email-beacon][src=?]", beacon_url("signed_in", ref: "ZyXwVuTsRqPoNmLkJiHg98")
  end

  test "a signed-out reader sent to sign in by a gated page keeps the ref" do
    get conversations_path(ref: REF)
    assert_response :redirect
    assert_equal REF, cookies[:email_ref]

    log_in_as(@arya)
    get play_path
    assert_select "img[data-email-beacon][src=?]", beacon_url("signed_in")
  end

  test "a redirect draws no beacon and leaves it for the next page" do
    nameless = User.create!(email: "nameless@example.com", name: "No Name")
    get play_path(ref: REF)
    log_in_as(nameless)
    get matches_path
    assert_response :redirect, "a player with no username is sent to pick one"
    assert cookies[:email_ref_signed_in].blank?

    get play_path
    assert_select "img[data-email-beacon][src=?]", beacon_url("signed_in")
  end

  test "a Turbo frame or a prefetch draws no beacon and leaves it for a real page" do
    get play_path(ref: REF)
    log_in_as(@arya)
    get play_path, headers: { "Turbo-Frame" => "chat" }
    assert_select "img[data-email-beacon]", count: 0
    get play_path, headers: { "X-Sec-Purpose" => "prefetch" }
    assert_select "img[data-email-beacon]", count: 0
    assert cookies[:email_ref_signed_in].blank?

    get play_path
    assert_select "img[data-email-beacon][src=?]", beacon_url("signed_in")
  end
end
