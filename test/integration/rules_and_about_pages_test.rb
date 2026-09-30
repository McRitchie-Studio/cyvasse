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
    assert_select "#rule-changes #changes-2015 li", count: Rulebook::CHANGES_2015.size
  end

  test "rules states the September 2026 trebuchet and king changes" do
    get rules_path

    assert_select "#rule-changes #changes-2026 li", count: Rulebook::CHANGES_2026.size
    assert_select "#rule-changes h3", text: "Implemented on September 29, 2026"
    assert_select "#rule-changes #changes-2026 li", text: /Trebuchet range rose from 3 to 4/
    assert_select "#rule-changes #changes-2026 li", text: /so neither can take a Trebuchet/
    assert_select "#unit-trebuchet dd", text: "4"
    assert_select "#unit-trebuchet dd", text: "Dragon, Spearman and Light Horse"
    assert_select "#combat p", text: /Every\s+Mountain blocks a shot, whichever army placed it/
    assert_select "#combat p", text: /Besides the Trebuchet and the Catapult, the King is the one unit that\s+trumps the Dragon/
    assert_select "#special-rules .special-rule-card[data-rule=dragon] p", text: /or a King it strays too close to/
    assert_select "#special-rules .special-rule-card[data-rule=range] p", text: /shoots 4 hexes/
  end

  test "rules states that elephants now move 2" do
    get rules_path

    assert_select "#rule-changes #changes-2026 li", text: "Elephants now move 2."
    assert_select "#unit-elephant dd", text: "2"
    assert_select "#unit-elephant dd", text: "3", count: 0
  end

  test "rules shows every unit with its vector art and stats" do
    get rules_path

    assert_select "#units .unit-card", count: 11
    Piece.all.each do |piece|
      assert_select "#unit-#{piece.slug}" do
        assert_select "h4", text: piece.name
        assert_select "img[alt=?][src*='/assets/pieces/vector/#{piece.slug}-']", piece.name
      end
    end
    assert_select "#unit-catapult dd", text: "Dragon"
    assert_select "#unit-king dd", text: "Dragon"
    assert_select "#unit-rabble dd", text: "—"
    assert_select "#class-range .unit-card", count: 3
  end

  test "rules states the stalemate rule: no legal move passes the turn, and neither side moving is a draw" do
    get rules_path

    assert_select "section#no-legal-move" do
      assert_select "h2", text: "No Legal Move"
      assert_select "p", text: /none of your units can move or attack, your turn passes/
      assert_select "p", text: /neither player can move, the game ends in a draw/
    end
    assert_select "#quick-start dd", text: /neither side can move, it is a draw/
  end

  # Production audit #5: the Special Rules cards were the legacy tutorial
  # screenshots, a Trebuchet printed with Movement 1 / Range 3. They are live
  # Rulebook cards now, so a stat change reaches them without an image edit.
  test "the special rules cards render the trebuchet and heavy horse from the rulebook" do
    get rules_path

    trebuchet = Rulebook.fetch("trebuchet")
    heavy_horse = Rulebook.fetch("heavyhorse")
    assert_select "#special-rules .special-rule-card[data-rule=range] .unit-card[data-unit=trebuchet]" do
      assert_select "h4", text: "Trebuchet"
      assert_select "dd[data-stat=movement]", text: trebuchet.movement
      assert_select "dd[data-stat=range]", text: trebuchet.range.to_s
      assert_select "dd[data-stat=movement]", text: "1", count: 0
      assert_select "dd[data-stat=range]", text: "3", count: 0
      assert_select "dd.unit-stat-marked[data-stat=range]"
    end
    assert_select "#special-rules .special-rule-card[data-rule=cavalry] .unit-card[data-unit=heavyhorse]" do
      assert_select "dd[data-stat=movement]", text: heavy_horse.movement
      assert_select "dd[data-stat=strength]", text: heavy_horse.strength
    end
    assert_select "#special-rules .special-rule-card[data-rule=cavalry] .unit-card[data-unit=lighthorse] dd[data-stat=movement]",
                  text: Rulebook.fetch("lighthorse").movement
    assert_select "#special-rules .special-rule-card[data-rule=trump] .unit-card[data-unit=spearman] dd[data-stat=trump]",
                  text: "Light Horse"
    assert_select "#special-rules img[src*='/assets/tutorial/']", 0
    assert_select "#special-rules .unit-card[id]", 0, "the units list owns the unit-<slug> ids"
  end

  # Production audit #6: "primary movement is 3 and the secondary is 2" was only
  # the Light Horse; each horse now gets its own first jump.
  test "the cavalry rule gives each horse its own movement" do
    get rules_path

    body = css_select("#special-rules .special-rule-card[data-rule=cavalry] p").text.squish
    assert_includes body, "The Light Horse's first jump reaches 3 and the Heavy Horse's reaches 2"
    assert_includes body, "the second jump reaches #{Rulebook::CAVALRY_SECOND_JUMP} for both"
    assert_no_match(/primary movement is 3/, body)
  end

  test "the rules count 19 pieces of 10 kinds, never 10 military pieces" do
    get rules_path

    page = response.parsed_body.text.squish
    assert_no_match(/10 military pieces/i, page)
    assert_select "#units p", text: /army has 19 pieces: 17 units of 10 kinds, and 2 Mountains/
  end

  test "the rules no longer promise an in-game tutorial" do
    get rules_path

    assert_no_match(/tutorial/i, response.parsed_body.text)
  end

  test "the dragon flies over everything but enemy range units and the enemy dragon" do
    get rules_path

    assert_select "#moving p", text: /enemy\s+Range units \(Crossbowman, Catapult and Trebuchet\) or the enemy\s+Dragon/
  end

  test "rules carries its banner image" do
    get rules_path

    assert_select "header.page-banner img[src*='/assets/backgrounds/rules/capture-the-king-']"
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
