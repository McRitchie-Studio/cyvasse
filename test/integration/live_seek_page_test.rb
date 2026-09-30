require "test_helper"

# [component] The Play Now searching page: the countdown, the copy, Cancel,
# "Play the computer now", which starts the computer match at once, and the
# splash's faces.
class LiveSeekPageTest < ActionDispatch::IntegrationTest
  setup do
    post live_seeks_path
    @seek = LiveSeek.last
  end

  test "the searching page offers the computer now, and still Cancel" do
    get live_seek_path(@seek)
    assert_select "h1", text: "Finding an opponent…"
    assert_select "[data-live-seek-target=message]", text: /you'll play a computer player/
    assert_select "form[action='#{computer_live_seek_path(@seek)}'][data-action='submit->live-seek#playComputer'] button",
                  text: "Play the computer now"
    assert_select "a[href='#{root_path}']", text: "Cancel"
    assert_select "[data-live-seek-splash-ms-value='5000'][data-live-seek-you-value='#{@seek.user.username}']"
  end

  test "play the computer now answers with the computer match" do
    post computer_live_seek_path(@seek, format: :json)
    body = response.parsed_body
    assert_equal "matched", body["status"]
    assert body["computer"]
    assert_equal match_path(@seek.reload.match), body["match_url"]
  end

  test "without JavaScript the button goes straight to the match" do
    post computer_live_seek_path(@seek)
    assert_redirected_to match_path(@seek.reload.match)
    assert @seek.match.away_user.computer?
  end

  # The splash wears the versus card's faces: your avatar from players/avatar
  # (a guest has no photo, so their piece), and quiet small-caps captions
  # rather than the old YOU and COMPUTER pills.
  test "the splash shows your piece avatar and quiet captions" do
    get live_seek_path(@seek)
    guest = @seek.user

    assert_select "[data-live-seek-target=splash] [data-side=me]" do
      assert_select "[data-avatar=piece][aria-label=?]", guest.player_name, 1
      assert_select ".player-caption", "You"
    end
    assert_select "[data-live-seek-target=splash] [data-side=them]" do
      assert_select "[data-live-seek-target=opponentAvatar] [data-avatar=pending]", 1
      assert_select ".player-caption[data-live-seek-target=computerTag][hidden]", "Computer"
    end
    assert_select ".live-seek-tag, [data-live-seek-target=youInitial], [data-live-seek-target=opponentInitial]", 0
  end
end
