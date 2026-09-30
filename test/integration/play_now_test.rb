require "test_helper"

# [integration] Play Now through real requests: a signed-out visitor becomes a
# guest with a session and a search; a second player is paired with them; the
# searching page's JSON reports the match with both names, and a computer
# player's avatar, rendered by the versus card's own partial.
class PlayNowTest < ActionDispatch::IntegrationTest
  test "the landing page's main button starts a live search" do
    get root_path
    assert_select "form[action='#{live_seeks_path}'] button", text: "Play Now"
  end

  test "a signed-out visitor plays as a guest and waits in the search" do
    post live_seeks_path
    seek = LiveSeek.last
    assert_redirected_to live_seek_path(seek)
    assert seek.user.guest?

    get live_seek_path(seek, format: :json)
    body = response.parsed_body
    assert_equal "searching", body["status"]
    assert body["ends_at"].present?
  end

  test "two visitors pressing Play Now are paired, each seeing the other" do
    arya = open_session
    arya.post live_seeks_path
    brienne = open_session
    brienne.post live_seeks_path

    arya_seek, brienne_seek = LiveSeek.order(:id).to_a
    arya.get live_seek_path(arya_seek, format: :json)
    brienne.get live_seek_path(brienne_seek, format: :json)

    assert_equal "matched", arya.response.parsed_body["status"]
    assert_equal brienne_seek.user.username, arya.response.parsed_body["opponent"]
    assert_equal arya_seek.user.username, brienne.response.parsed_body["opponent"]
    assert_equal false, arya.response.parsed_body["computer"]
    # A person's avatar is their piece, as on the versus card, not a portrait.
    avatar = Nokogiri::HTML.fragment(arya.response.parsed_body["opponent_avatar"])
    assert_equal 1, avatar.css("[data-avatar=piece][aria-label='#{brienne_seek.user.player_name}']").size
    assert_empty avatar.css("[data-avatar=bot-portrait]")
    assert_nil arya.response.parsed_body["opponent_portrait"], "the bare portrait URL is gone"
    assert_equal arya.response.parsed_body["match_url"], brienne.response.parsed_body["match_url"]
  end

  test "meeting a computer player, the splash's JSON carries its seeded portrait" do
    post live_seeks_path
    seek = LiveSeek.last
    post computer_live_seek_path(seek)
    get live_seek_path(seek, format: :json)

    body = response.parsed_body
    bot = seek.reload.match.away_user
    assert_equal true, body["computer"]
    assert_equal "bots/#{bot.username}.webp", bot.portrait
    img = Nokogiri::HTML.fragment(body["opponent_avatar"]).at_css("img[data-avatar=bot-portrait]")
    assert_match %r{\A/assets/bots/#{bot.username}-[0-9a-f]+\.webp\z}, img["src"]
    assert_equal bot.player_name, img["alt"]
    get img["src"]
    assert_response :success
  end

  test "a computer player with no seeded portrait shows its piece on the splash" do
    post live_seeks_path
    seek = LiveSeek.last
    post computer_live_seek_path(seek)
    seek.reload.match.away_user.update_columns(portrait: nil)
    get live_seek_path(seek, format: :json)
    assert_equal true, response.parsed_body["computer"]
    avatar = Nokogiri::HTML.fragment(response.parsed_body["opponent_avatar"])
    assert_empty avatar.css("[data-avatar=bot-portrait]")
    assert_equal 1, avatar.css("[data-avatar=bot-fallback]").size
  end

  test "you cannot read someone else's search" do
    other = open_session
    other.post live_seeks_path
    post live_seeks_path
    get live_seek_path(LiveSeek.order(:id).first, format: :json)
    assert_response :not_found
  end

  test "a search that fails to settle is logged, not lost" do
    post live_seeks_path
    seek = LiveSeek.last
    locked = LiveSeek.method(:locked)
    LiveSeek.define_singleton_method(:locked) { |*| raise "boom" }
    assert_difference -> { ErrorLog.where(target: seek).count }, 1 do
      get live_seek_path(seek, format: :json)
    rescue RuntimeError
      nil
    end
  ensure
    LiveSeek.define_singleton_method(:locked, locked)
  end
end
