require "test_helper"

# [component] /rules and /about render their sections and images publicly.
class RulesAndAboutPagesTest < ActionDispatch::IntegrationTest
  test "rules renders every rules section, signed out" do
    get rules_path

    assert_response :success
    assert_select "h1", text: "Rules"
    %w[quick-start goal pregame who-goes-first game moving combat special-rules units rule-changes].each do |id|
      assert_select "section##{id}", 1, "section ##{id}"
    end
    assert_select "#combat p", text: /Spearman will always defeat a Light Horse/
    assert_select "#rule-changes li", count: Rulebook::CHANGES_2015.size
  end

  test "rules shows every unit with its vector art and stats" do
    get rules_path

    assert_select ".unit-card", count: 11
    Piece.all.each do |piece|
      assert_select "#unit-#{piece.slug}" do
        assert_select "h4", text: piece.name
        assert_select "img[alt=?][src*='/assets/pieces/vector/#{piece.slug}-']", piece.name
      end
    end
    assert_select "#unit-catapult dd", text: "Dragon"
    assert_select "#unit-king dd", text: "—"
    assert_select "#class-range .unit-card", count: 3
  end

  test "rules carries the four tutorial images where the tutorial used them" do
    get rules_path

    %w[range cavalry dragon trump].each do |image|
      assert_select "#special-rules .tutorial-card[data-tutorial=#{image}] img[src*='/assets/tutorial/#{image}-'][alt]"
    end
    assert_select "header.page-banner img[src*='/assets/backgrounds/cyvasse_rules_background-']"
  end

  test "about credits Alex and thanks every mentor and gSchool" do
    get about_path

    assert_response :success
    assert_select "h1", text: "About"
    assert_select "#author figcaption", text: "Alex McRitchie"
    assert_select "#author img[alt='Alex McRitchie'][src*='/assets/thanks/alexmcritchie-']"
    assert_select "#story p", text: /August 8, 2014/

    thanked = [ "Jeff Taggart", "Bobby Wilson", "Bobby Blackstock", "Sean Smith", "Zach Klabunde", "Aaron Gray" ]
    assert_select ".thanks-profile", count: thanked.size
    thanked.each { |name| assert_select ".thanks-profile img[alt=?]", name }
    assert_select "#gschool img[src*='/assets/thanks/gschool-']"
  end

  test "every external about link opens safely in a new tab" do
    get about_path

    links = css_select(".about-page a[href^='http']")
    assert_operator links.size, :>=, 10
    links.each do |a|
      assert_equal "_blank", a["target"], a["href"]
      assert_equal "noopener noreferrer", a["rel"], a["href"]
      assert a["href"].start_with?("https://"), a["href"]
    end
  end

  test "the sidebar links both pages" do
    get root_path

    assert_select "a[href='/rules']"
    assert_select "a[href='/about']"
  end
end
