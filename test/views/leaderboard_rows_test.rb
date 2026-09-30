require "test_helper"

# [component] The leaderboard rows (leaderboards/_rows) and the landing card
# (leaderboards/_card), rendered alone: the live board shows rank, points,
# wins and games finished; the all-time board wins and losses; each board's
# short labels are spelled out in a key line and an <abbr title>.
class LeaderboardRowsTest < ActionView::TestCase
  def row(name, rank:, points:, wins:, games:, losses: games - wins)
    Leaderboard::Row.new(rank:, user: User.new(id: rank, username: name), points:, wins:, games:, losses:)
  end

  setup { view.define_singleton_method(:current_user) { nil } }

  test "a live row shows rank, points, wins and games" do
    render partial: "leaderboards/rows",
           locals: { board: "live", rows: [ row("arya", rank: 1, points: 7, wins: 2, games: 3), row("Guest_4821", rank: 2, points: 1, wins: 0, games: 1) ] }

    assert_select "ol.leaderboard-rows.is-live"
    assert_select "[data-leaderboard-row=arya]" do
      assert_select "[data-stat=rank]", "1"
      assert_select "[data-stat=points]", /\A\s*7\s*pts\s*\z/
      assert_select "[data-stat=wins]", /\A\s*2\s*W\s*\z/
      assert_select "[data-stat=games]", /\A\s*3\s*G\s*\z/
      assert_select "[data-stat=losses]", 0
    end
    assert_select "[data-leaderboard-row=Guest_4821] [data-stat=points]", /\A\s*1\s*pt\s*\z/
  end

  test "the live labels are spelled out: a key line, and a title on each short label" do
    render partial: "leaderboards/rows",
           locals: { board: "live", rows: [ row("arya", rank: 1, points: 7, wins: 2, games: 3), row("Guest_4821", rank: 2, points: 1, wins: 0, games: 1) ] }

    assert_select "[data-leaderboard-key]", 1 do |key|
      assert_equal "pts points · W wins · G games finished", key.text.squish
    end
    assert_select "[data-leaderboard-row=arya]" do
      assert_select "[data-stat=points] abbr[title=Points]", "pts"
      assert_select "[data-stat=wins] abbr[title=Wins]", "W"
      assert_select "[data-stat=games] abbr[title='Games finished']", "G"
    end
    assert_select "[data-leaderboard-row=Guest_4821] [data-stat=points] abbr[title=Point]", "pt"
  end

  test "the all-time labels are spelled out too" do
    render partial: "leaderboards/rows", locals: { board: "all-time", rows: [ row("arya", rank: 1, points: nil, wins: 12, games: 15) ] }

    assert_select "[data-leaderboard-key]", 1 do |key|
      assert_equal "W wins · L losses", key.text.squish
    end
    assert_select "[data-stat=wins] abbr[title=Wins]", "W"
    assert_select "[data-stat=losses] abbr[title=Losses]", "L"
  end

  test "an all-time row shows wins and losses, no points" do
    render partial: "leaderboards/rows", locals: { board: "all-time", rows: [ row("arya", rank: 1, points: nil, wins: 12, games: 15) ] }

    assert_select "[data-leaderboard-row=arya] [data-stat=wins]", /12\s*W/
    assert_select "[data-leaderboard-row=arya] [data-stat=losses]", /3\s*L/
    assert_select "[data-stat=points]", 0
  end

  test "the landing card shows the live columns, or the Play Now invitation when empty" do
    render partial: "leaderboards/card", locals: { rows: [ row("arya", rank: 1, points: 3, wins: 1, games: 1) ] }
    assert_select "[data-leaderboard-card] [data-leaderboard-row=arya] [data-stat=points]", /3/
    assert_select "[data-leaderboard-card] [data-leaderboard-key]", /pts points · W wins · G games finished/
    assert_select "[data-leaderboard-empty]", 0

    render partial: "leaderboards/card", locals: { rows: [] }
    assert_select "[data-leaderboard-empty]", /Be the first on the board/
  end

  test "a live row's grid has a track for each of its three numbers" do
    css = Rails.root.join("app/assets/tailwind/application.css").read
    assert_match(/\.leaderboard-rows\.is-live \.leaderboard-row \{\s*grid-template-columns: 2rem minmax\(0, 1fr\) auto auto auto;/, css)
  end
end
