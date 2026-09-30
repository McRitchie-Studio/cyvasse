require "test_helper"

# [integration] The remote runner's API (/api/bot): bearer token only, the
# token's own matches only, and the same checks a browser's moves get.
class Api::BotTest < ActionDispatch::IntegrationTest
  include MatchPlay

  setup do
    @tyrion = User.create!(legacy_id: 3, username: "tyrion", name: "Tyrion Lannister")
    _record, @token = BotToken.issue!(@tyrion)
    @arya = make_player("arya")
  end

  def auth(token = @token) = { "Authorization" => "Bearer #{token}", "Accept" => "application/json" }

  def bot_get(path, token: @token)
    get path, headers: auth(token)
    response.parsed_body
  end

  def bot_post(path, token: @token, **body)
    post path, params: body.to_json, headers: auth(token).merge("Content-Type" => "application/json")
    response.parsed_body
  end

  # A correspondence match with Tyrion in the home seat as a remote player
  # (not an in-app computer seat), so the recorded game's home turns are his.
  def match_with_tyrion
    Match.create!(home_user: @tyrion, away_user: @arya, match_status: Match::ACCEPTED, match_against: "human",
                  turn: 0, time_of_last_move: Time.current)
  end

  test "no token, a wrong token, a revoked token: 401" do
    get api_bot_inbox_path
    assert_response :unauthorized
    get api_bot_inbox_path, headers: auth("cyb_nope")
    assert_response :unauthorized

    BotToken.last.revoke!
    get api_bot_inbox_path, headers: auth
    assert_response :unauthorized
  end

  test "a player's browser session is not a way in" do
    log_in_as(@arya)
    get api_bot_inbox_path, headers: { "Accept" => "application/json" }
    assert_response :unauthorized
  end

  test "the inbox lists his matches with the action each waits on, and stamps the heartbeat" do
    match = match_with_tyrion
    body = bot_get(api_bot_inbox_path)
    assert_response :success
    assert_equal [ { "id" => match.id, "action" => "setup", "opponent" => "arya", "phase" => "setup", "live" => false } ],
                 body["matches"].map { _1.slice("id", "action", "opponent", "phase", "live") }
    assert BotToken.heard_from?(@tyrion)
  end

  test "he sets up, plays whole turns and is refused an illegal one, as a browser would be" do
    match = match_with_tyrion
    body = bot_post(setup_api_bot_match_path(match), lineup: home_lineup)
    assert_response :success
    assert_equal true, body.dig("state", "you", "ready")

    match.set_up!(@arya, away_lineup)
    assert_equal "move", bot_get(api_bot_inbox_path)["matches"].first["action"], "home moves first in the recorded game"

    body = bot_post(moves_api_bot_match_path(match), steps: [ [ 52, 1 ] ])
    assert_response :unprocessable_entity
    assert_match(/not allowed/, body["error"])

    first = GAME.fetch("turns").first
    assert_equal Match::HOME, first.fetch("mover")
    body = bot_post(moves_api_bot_match_path(match), steps: steps_for(first))
    assert_response :success
    assert_equal false, body.dig("state", "your_turn")
    assert_nil bot_get(api_bot_inbox_path)["matches"].first["action"], "now it is Arya's move"
  end

  test "he reads messages sent to him since a cursor and answers in the match chat" do
    match = match_with_tyrion
    first = Message.post_in_match!(match, @arya, "Good luck, little lion.")
    body = bot_get(api_bot_inbox_path)
    assert_equal [ { "id" => first.id, "match_id" => match.id, "from" => "arya", "text" => "Good luck, little lion." } ],
                 body["messages"].map { _1.except("sent_at") }
    assert_equal first.id, body["cursor"]
    assert_empty bot_get(api_bot_inbox_path(after: body["cursor"]))["messages"]

    body = bot_post(api_bot_match_messages_path(match), message: "Luck is for dice. This is cyvasse.")
    assert_response :created
    assert_equal @arya, Message.find(body["id"]).receiver

    bot_post(api_bot_match_messages_path(match), message: "   ")
    assert_response :unprocessable_entity
  end

  test "a live match: the inbox settles its clocks and he plays it like any other" do
    match = Match.start_live!(@arya, @tyrion)
    assert_equal "setup", bot_get(api_bot_inbox_path)["matches"].first["action"]
    body = bot_post(setup_api_bot_match_path(match), lineup: away_lineup)
    assert_response :success
    assert_equal true, body.dig("state", "you", "ready")
    assert_equal "away", body.dig("state", "seat")
  end

  test "a Play Now game the in-app computer plays as him is not listed, nor its chat" do
    match = Match.start_live!(@arya, @tyrion)
    match.update!(away_bot: true) # the seat Play Now gives its in-app computer
    Message.post_in_match!(match, @arya, "Hello, computer.")
    body = bot_get(api_bot_inbox_path)
    assert_empty body["matches"]
    assert_empty body["messages"]
    bot_post(moves_api_bot_match_path(match), steps: [ [ 1, 2 ] ])
    assert_response :unprocessable_entity
  end

  test "another player's match is a 404 for everything" do
    brienne = make_player("brienne")
    theirs = Match.challenge!(@arya, brienne.username)
    bot_get(api_bot_match_path(theirs))
    assert_response :not_found
    bot_post(setup_api_bot_match_path(theirs), lineup: home_lineup)
    assert_response :not_found
    bot_post(api_bot_match_messages_path(theirs), message: "hello")
    assert_response :not_found
    assert_equal 0, theirs.messages.count
  end
end
