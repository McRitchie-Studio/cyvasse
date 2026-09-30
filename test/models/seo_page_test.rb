require "test_helper"

# [unit] SeoPage, the one list of indexed pages and their copy (task
# cyvasse-seo-profile): unique, within the lengths a results page shows, and
# the sitemap's lastmod.
class SeoPageTest < ActiveSupport::TestCase
  include LiveResults

  test "titles and descriptions are unique and fit a results page" do
    titles = SeoPage::PAGES.map(&:title)
    descriptions = SeoPage::PAGES.map(&:description)

    assert_equal titles.uniq, titles, "every page has its own <title>"
    assert_equal descriptions.uniq, descriptions, "every page has its own description"
    SeoPage::PAGES.each do |page|
      assert_operator page.title.length, :<=, 60, "#{page.key} title is #{page.title.length} characters"
      assert_includes 70..160, page.description.length, "#{page.key} description is #{page.description.length} characters"
      assert_includes page.title, "Cyvasse", "#{page.key} title names the game"
    end
  end

  test "the home page targets the searches people make" do
    home = SeoPage.find(:home)

    assert_match(/\ACyvasse/, home.title)
    assert_match(/Game of Thrones/, home.title)
    assert_match(/free/i, home.description)
    assert_match(/Cyvasse Rules/, SeoPage.find(:rules).title)
    assert_match(/Play Cyvasse Online/, SeoPage.find(:play).title)
  end

  test "the sitemap lists the public pages and leaves the all-time tab to its link" do
    assert_equal %w[/ /play /rules /pieces /about /leaderboard], SeoPage.sitemap_pages.map(&:path)
  end

  test "find refuses a page that is not named" do
    assert_raises(KeyError) { SeoPage.find(:matches) }
  end

  test "static pages date from their copy; the leaderboard from the last finished game" do
    board = SeoPage.find(:leaderboard)
    Match.finished.delete_all

    assert_equal SeoPage::CONTENT_UPDATED, SeoPage.lastmod(board), "no finished game: the copy date"

    later = SeoPage::CONTENT_UPDATED + 3
    live_result(User.create!(email: "arya@example.com", name: "Arya", username: "arya"),
                User.create!(email: "sansa@example.com", name: "Sansa", username: "sansa"),
                winner: nil, finished_at: later.in_time_zone.noon)

    assert_equal later, SeoPage.lastmod(board)
    assert_equal later, SeoPage.lastmod(SeoPage.find(:home)), "the home page carries the top ten"
    assert_equal SeoPage::CONTENT_UPDATED, SeoPage.lastmod(SeoPage.find(:rules))
  end

  test "the FAQ answers every question and names the board the rules use" do
    faq = SeoPage.faq

    assert_operator faq.size, :>=, 4
    faq.each { |question, answer| assert question.end_with?("?") && answer.present? }
    assert_match(/#{CyvasseRules::Board::HEX_COUNT} hexes/, faq.first.last)
  end
end
