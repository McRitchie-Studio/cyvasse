require "test_helper"

# [integration] "Take back my seat" through the controller, as JSON exactly as
# the board posts it: the seat's own player gets the seat and the new state,
# anyone else a refusal, and the match page carries the control and its URL.
class TakeBackSeatIntegrationTest < ActionDispatch::IntegrationTest
  include MatchPlay

  setup do
    @home = make_player("arya")
    @away = make_player("brienne")
    @match = Match.start_live!(@home, @away, rng: Random.new(7))
    @match.set_up!(@home, home_lineup)
    @match.set_up!(@away, away_lineup)
    @match.reload.update_columns(home_bot: true, home_strikes: 2, whos_turn: Match::AWAY, clock_started_at: Time.current)
  end

  def post_seat
    post seat_match_path(@match), params: "{}", headers: { "Content-Type" => "application/json", "Accept" => "application/json" }
    response.parsed_body
  end

  test "the seat's own player takes it back and gets the new state" do
    log_in_as(@home)
    body = post_seat

    assert_response :success
    assert_equal({ "you" => false, "opponent" => false }, body.dig("state", "live", "taken_over"))
    assert_equal true, body.dig("state", "live", "took_back", "you")
    assert_not @match.reload.bot_seat?(:home)
  end

  test "the opponent cannot take the seat, and a stranger cannot see the match" do
    log_in_as(@away)
    body = post_seat
    assert_response :unprocessable_entity
    assert_match(/already yours/, body["error"])

    log_in_as(make_player("cersei"))
    post_seat
    assert_response :not_found
    assert @match.reload.bot_seat?(:home)
    assert_equal 0, ErrorLog.count, "a refusal is an answer, not an error"
  end

  test "the match page carries the control in the status card, and the URL it posts to" do
    log_in_as(@home)
    get match_path(@match)

    assert_select "[data-controller=cyvasse-match][data-cyvasse-match-seat-url-value=?]", seat_match_path(@match)
    assert_select ".match-panel-status [data-match-slot=take-back-seat][hidden] button[data-action='cyvasse-match#takeBackSeat']",
                  text: "Take back my seat"
    assert_select ".match-panel-status [data-cyvasse-match-target=notice] button[data-action='cyvasse-match#dismissNotice']"
  end
end
