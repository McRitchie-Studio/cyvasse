require "test_helper"

# [component] Task cyvasse-standard-page-headers (Alex McRitchie, "run the UI
# cleanup for all the apps"): every interior page with a title row, and every
# admin page, renders studio-engine's studio/_page_header with a crumb trail from
# the app's parent map (config/initializers/studio_crumbs.rb) and its title as
# the page's one h1. Each link the old header carried (a back link, the admin
# eyebrow, the leaderboard's tabs) stays reachable in the row. The marketing
# heroes and the game surfaces keep their own headers, so they carry no row.
# "One h1" counts the page's own (page_h1s): the engine navbar draws the brand as
# an h1 on every page (brand_heading), which this task leaves as it is.
class PageHeadersTest < ActionDispatch::IntegrationTest
  include MatchPlay

  ROW = ".page-header".freeze

  setup do
    @arya = make_player("arya")
    @brienne = make_player("brienne")
    @admin = User.create!(email: "admin@example.com", name: "Admin", role: "admin", username: "boss")
    @match = Match.challenge!(@arya, "brienne")
    Message.create!(sender: @arya, receiver: @brienne, message: "good game", match: @match)
    @key = [ @arya.id, @brienne.id ].minmax.join("-")
  end

  # The page's own h1s: every h1 but the navbar's brand.
  def page_h1s = css_select("h1") - css_select("header[data-pin=nav] h1")

  def assert_standard_header(name, title, ancestors)
    assert_response :success, name
    assert_equal 1, css_select(ROW).size, "#{name}: one engine page header"
    assert_equal [ title ], page_h1s.map { |h1| h1.text.squish }, "#{name}: one h1, the header's title"
    assert_select "#{ROW} h1.page-header-title", { count: 1 }, name
    assert_equal ancestors, css_select("#{ROW} nav.page-header-crumbs a.page-header-crumb").map { |a| a.text.strip },
                 "#{name}: the crumb trail"
    if ancestors.any?
      assert_select "#{ROW} .page-header-crumb-current[aria-current=page]", { count: 1 }, name
      assert_select "#{ROW} a.page-header-parent", 1
    else
      assert_select "#{ROW} nav.page-header-crumbs", 0
    end
    ids = css_select("[id]").map { |el| el["id"] }
    assert_equal ids.uniq, ids, "#{name}: duplicate ids #{ids.tally.select { |_, n| n > 1 }.keys}"
  end

  test "[component] the public title-row pages render the page header under a Home crumb" do
    { "/privacy" => "Privacy Policy", "/terms" => "Terms of Service", "/pieces" => "The Pieces",
      "/leaderboard" => "Leaderboard" }.each do |path, title|
      get path
      assert_standard_header(path, title, [ "Home" ])
      assert_select "#{ROW} a.page-header-crumb[href='/']", 1
    end
  end

  test "[component] the legal pages keep the policy's gold links off the crumbs" do
    get "/privacy"
    assert_select "article[data-legal-page=privacy] > #{ROW}", 1
    assert_select "article .legal-body a[href='mailto:team@mcritchie.studio']"
    assert_select ".legal-body #{ROW}", 0
  end

  test "[component] the leaderboard's two boards are the header's tabs" do
    { leaderboard_path => "Live", leaderboard_path(board: "all-time") => "All-time" }.each do |path, current|
      get path
      assert_standard_header(path, "Leaderboard", [ "Home" ])
      assert_select "#{ROW} nav.page-header-tabs[aria-label=Leaderboards] a.page-header-tab", 2
      assert_select "#{ROW} a.page-header-tab[aria-current=page]", { text: current, count: 1 }, path
      assert_select "#{ROW} a.page-header-tab[href=?]", leaderboard_path(board: "all-time")
    end
    assert_select ".leaderboard-tabs, .leaderboard-tab", 0
  end

  test "[component] the leaderboard's sign-in sits under the Leaderboard, its card under the row" do
    get join_leaderboard_path
    assert_standard_header("join", "Save your games", [ "Home", "Leaderboard" ])
    assert_select "#{ROW} .page-header-crumb-current", text: "Sign in"
    assert_select "#{ROW} ~ .card[data-join-leaderboard] form[action=?]", magic_link_request_path
  end

  test "[component] My games, Chat and a conversation sit under Home and Chat" do
    log_in_as(@arya)
    get matches_path
    assert_standard_header("my games", "My games", [ "Home" ])
    assert_select "form[action=?] input[name=username]", matches_path
    assert_select "a[data-chat-link]"

    get username_path(return_to: matches_path)
    assert_standard_header("username", "Your username", [ "Home", "My games" ])
    assert_select "#{ROW} ~ .card form[action=?] input[name=username]", username_path

    get conversations_path
    assert_standard_header("chat", "Chat", [ "Home" ])

    get conversation_path(@brienne.id)
    assert_standard_header("conversation", "brienne", [ "Home", "Chat" ])
    assert_select "#{ROW} a.page-header-parent[href=?]", conversations_path
    assert_select "#{ROW} h1 [aria-hidden=true] [data-avatar]", 1
    assert_select "#{ROW} .page-header-crumb-current", text: "brienne"
  end

  test "[component] Conversations is the admin root; the other admin pages sit under it" do
    log_in_as(@admin)
    get admin_conversations_path
    assert_standard_header("admin conversations", "Conversations", [])
    assert_select "#{ROW} nav.page-header-links a[data-board-link][href=?]", admin_message_board_path
    assert_select "form[action=?] input[name=q]", admin_conversations_path

    { admin_message_board_path => "Message Board", admin_sign_ins_path => "Email sign-ins",
      admin_conversation_path(@key) => "arya & brienne",
      admin_match_path(@match) => "Match ##{@match.id}: arya vs brienne" }.each do |path, title|
      get path
      assert_standard_header(path, title, [ "Conversations" ])
      assert_select "#{ROW} a.page-header-crumb[href=?]", admin_conversations_path
    end
    assert_select "#{ROW} .page-header-crumb-current", text: "Match ##{@match.id}"

    get admin_conversation_path(@key)
    assert_select "#{ROW} nav.page-header-links", 0
    get admin_conversation_path(@key, game: @match.id)
    assert_select "#{ROW} nav.page-header-links a[href=?]", admin_conversation_path(@key), text: "Every game"
  end

  test "[component] the marketing heroes and the game surfaces carry no page header row" do
    %w[/ /rules /about /night /play].each do |path|
      get path
      assert_response :success, path
      assert_select ROW, { count: 0 }, path
      assert_equal 1, page_h1s.size, "#{path}: the page's own h1"
    end
    log_in_as(@arya)
    get match_path(@match)
    assert_response :success
    assert_select ROW, 0
    assert_select "h1.match-versus", 1
  end
end
