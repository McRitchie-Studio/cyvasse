require "test_helper"

# [integration] A player who arrives from an email (the hub's click redirect
# adds ?ref=<delivery token>) is credited to it: the page carries the beacon
# URL for the board, and the first signed-in page fires the signed_in beacon
# exactly once.
class EmailRefTest < ActionDispatch::IntegrationTest
  REF = "AbCdEfGhIjKlMnOpQrSt12"

  setup do
    @arya = User.create!(email: "arya@example.com", name: "Arya", username: "arya")
  end

  test "a visitor with no ref gets no beacon and no meta tag" do
    get play_path
    assert_select "meta[name='email-goal-url']", count: 0
    assert_select "img[data-email-beacon]", count: 0
  end

  test "a ref is remembered and the board gets the hub's beacon URL" do
    get play_path(ref: REF)
    assert_select "meta[name='email-goal-url'][content=?]", "https://mcritchie.studio/e/g/#{REF}?g="
    get rules_path
    assert_select "meta[name='email-goal-url'][content=?]", "https://mcritchie.studio/e/g/#{REF}?g="
  end

  test "a malformed ref is ignored" do
    get play_path(ref: "<script>")
    assert_select "meta[name='email-goal-url']", count: 0
  end

  test "signing in fires the signed_in beacon on one page only" do
    get play_path(ref: REF)
    assert_select "img[data-email-beacon]", count: 0, message: "not signed in yet"

    log_in_as(@arya)
    get play_path
    assert_select "img[data-email-beacon][src=?]", "https://mcritchie.studio/e/g/#{REF}?g=signed_in"
    get play_path
    assert_select "img[data-email-beacon]", count: 0
  end

  test "a second email's ref counts its own sign-in" do
    log_in_as(@arya)
    get play_path(ref: REF)
    get play_path(ref: "ZyXwVuTsRqPoNmLkJiHg98")
    assert_select "img[data-email-beacon][src$=?]", "ZyXwVuTsRqPoNmLkJiHg98?g=signed_in"
  end
end
