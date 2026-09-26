require "application_system_test_case"

# [e2e] Two players in two browsers: a challenge by username, both armies set
# up through the board, and the first move, which the other player's open
# board picks up on its own (polling) and which the server mails them about.
class OnlineMatchSystemTest < ApplicationSystemTestCase
  BOARD = "[data-controller=cyvasse-match]".freeze

  setup do
    @arya = User.create!(email: "arya@example.com", name: "Arya", username: "arya")
    @brienne = User.create!(email: "brienne@example.com", name: "Brienne", username: "brienne")
  end

  test "challenge, set up, and the first move" do
    sign_in(@arya)
    visit matches_path
    fill_in "Challenge a player", with: "brienne"
    click_on "Challenge"

    assert_text "Challenge sent to brienne"
    assert_selector BOARD
    assert_selector "svg.cyvasse-board g.hex", count: 91
    assert_selector ".cyvasse-dock .dock-unit", count: 19
    click_on "Random Setup"
    click_on "Submit army"
    assert_selector "[role=status]", text: "Waiting for brienne to accept"
    match = Match.last

    using_session("brienne") do
      sign_in(@brienne)
      visit matches_path
      within("[data-section=set-up-your-army]") { click_on "vs arya" }
      assert_selector "[role=status]", text: "arya challenged you"
      assert_no_selector "svg.cyvasse-board g.hex.has-unit", wait: 0.5
      click_on "Accept"
      assert_text "Challenge accepted"
      assert_no_selector "svg.cyvasse-board g.hex.has-unit[data-team='0']", wait: 0.5
      click_on "Random Setup"
      click_on "Submit army"
      assert_selector "#{BOARD}[data-phase=play]"
      assert_selector "svg.cyvasse-board g.hex.has-unit[data-team='1']", count: 19
      assert_selector "svg.cyvasse-board g.hex.has-unit[data-team='0']", count: 19
    end

    first_mover = match.reload.user_to_move
    waiting = first_mover == @arya ? "brienne" : :default
    mover = first_mover == @arya ? :default : "brienne"

    Capybara.using_session(waiting) do
      visit match_path(match)
      assert_selector "#{BOARD}[data-your-turn=false][data-phase=play]"
      assert_selector "[role=status]", text: "waiting for #{first_mover.username} to move"
      page.execute_script("document.querySelector('#{BOARD}').dataset.cyvasseMatchPollMsValue = '300'")
    end

    Capybara.using_session(mover) do
      visit match_path(match)
      assert_selector "#{BOARD}[data-your-turn=true]"
      set_instant_pace
      take_a_turn
      assert_selector "#{BOARD}[data-your-turn=false]", wait: 10
      assert_no_selector "[role=alert]:not([hidden])", wait: 0
    end

    assert_equal 2, match.reload.turn
    next_player = match.user_to_move
    assert_not_equal first_mover, next_player
    assert Studio::EmailDelivery.exists?(email_key: "MatchMailer#your_turn", to: next_player.email)

    Capybara.using_session(waiting) do
      assert_selector "#{BOARD}[data-your-turn=true]", wait: 10
      assert_selector "[role=status]", text: "Turn 2: your move."
      assert_selector "svg.cyvasse-board g.hex.is-last-move", minimum: 2
    end
  end

  private

  def sign_in(user)
    # The link's confirm page submits itself and lands on the front page.
    visit link_path(token: Studio::Link.create_magic_link(email: user.email).token)
    assert_text "Signed in as #{user.name}"
  end

  def set_instant_pace
    page.execute_script("document.querySelector('#{BOARD}').dataset.cyvasseMatchPaceValue = '0'")
  end

  # Select our units in turn until one has somewhere to go and take the first
  # move offered; a cavalry unit then jumps again.
  def take_a_turn
    all("svg.cyvasse-board g.hex.has-unit[data-team='1']").map { |node| node["data-hex"] }.each do |hex|
      find("svg.cyvasse-board g.hex[data-hex='#{hex}']").click
      target = first("svg.cyvasse-board g.hex.is-attack, svg.cyvasse-board g.hex.is-move", minimum: 0, wait: 0)
      next unless target

      target.click
      if page.has_selector?("[role=status]", text: "jumps again", wait: 0.3)
        first("svg.cyvasse-board g.hex.is-attack, svg.cyvasse-board g.hex.is-move").click
      end
      return
    end
    flunk "none of our units could move"
  end
end
