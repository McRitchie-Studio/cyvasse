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
    assert_select "#combat p", text: /A Rabble that attacks a King takes it/
    assert_select "#rule-changes #changes-2015 li", count: Rulebook::CHANGES_2015.size
  end

  test "rules states the September 2026 trebuchet and king changes" do
    get rules_path

    assert_select "#rule-changes #changes-2026 li", count: Rulebook::CHANGES_2026.size
    assert_select "#rule-changes h3", text: "Implemented on September 29, 2026"
    assert_select "#rule-changes #changes-2026 li", text: /Trebuchet range rose from 3 to 4/
    assert_select "#rule-changes #changes-2026 li", text: /so neither can take a Trebuchet/, count: 0
    assert_select "#unit-trebuchet dd", text: "4"
    assert_equal [ "Trumps Dragon" ], css_select("#unit-trebuchet dd[data-stat=trump] img").map { _1["alt"] }
    assert_select "#combat p", text: /Every\s+Mountain blocks a shot, whichever army placed it/
    assert_select "#combat p", text: /Besides the Trebuchet and the Catapult, the King is the one unit that\s+trumps the Dragon/
    assert_select "#special-rules .special-rule-card[data-rule=dragon] p", text: /only a Trebuchet, Catapult, King or Dragon can take it/
    assert_select "#special-rules .special-rule-card[data-rule=range] .unit-card[data-unit=trebuchet] dd[data-stat=range]", text: "4"
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
    assert_select "#unit-catapult dd[data-stat=trump] img[alt='Trumps Dragon']", 1
    assert_select "#unit-king dd[data-stat=trump] img[alt='Trumps Dragon']", 1
    assert_select "#unit-rabble dd[data-stat=trump] img[alt='Trumps King']", 1
    %w[spearman crossbowman].each do |slug|
      assert_select "#unit-#{slug} dd[data-stat=trump]", text: "—"
      assert_select "#unit-#{slug} dd[data-stat=trump] img", 0
    end
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
      # Alex, 2026-09-29: Range heads a range unit's card, and only Range is marked.
      assert_select ".unit-stat:first-child[data-stat=range]"
      assert_select ".unit-stat-marked", 1
      assert_select ".unit-stat-marked[data-stat=range] > dd[data-stat=range]"
    end
    assert_equal %w[range strength movement trump],
                 css_select("#special-rules [data-rule=range] .unit-card .unit-stat").map { _1["data-stat"] }
    assert_select "#special-rules .special-rule-card[data-rule=cavalry] .unit-card[data-unit=heavyhorse]" do
      assert_select "dd[data-stat=movement]", text: heavy_horse.movement
      assert_select "dd[data-stat=strength]", text: heavy_horse.strength
    end
    # Alex, 2026-09-29: "just show the heavy horse because people will get it".
    assert_equal %w[heavyhorse], css_select("#special-rules .special-rule-card[data-rule=cavalry] .unit-card").map { _1["data-unit"] }
    assert_select "#special-rules .special-rule-card[data-rule=cavalry] .unit-stat-marked[data-stat=movement] dd", text: "3 + 1"
    assert_select "#special-rules .special-rule-card[data-rule=trump] .unit-card[data-unit=rabble] " \
                  ".unit-stat-marked[data-stat=trump] dd img[alt='Trumps King']", 1
    assert_select "#special-rules img[src*='/assets/tutorial/']", 0
    assert_select "#special-rules .unit-card[id]", 0, "the units list owns the unit-<slug> ids"
  end

  # Production audit #6: "primary movement is 3 and the secondary is 2" was only
  # the Light Horse. Since Alex cut the Special Rules copy (2026-09-29) the
  # cavalry card states the rule alone and each horse's jumps live on its unit
  # card (4 + 1 and 3 + 1).
  test "the cavalry rule states the double move and leaves the jumps to the unit cards" do
    get rules_path

    body = css_select("#special-rules .special-rule-card[data-rule=cavalry] p").text.squish
    assert_equal "Cavalry units move or attack twice a turn.", body
    assert_no_match(/primary movement is 3/, body)
    assert_select "#unit-lighthorse dd", text: "4 + 1"
    assert_select "#unit-heavyhorse dd", text: "3 + 1"
  end

  # [component] Alex, 2026-09-29: "All of these descriptions need to be cut into
  # a 1/3". The longest body before the cut ran about 290 characters.
  test "every special rules body is one or two short sentences" do
    get rules_path

    bodies = css_select("#special-rules .special-rule-card p").map { _1.text.squish }
    assert_equal 4, bodies.size
    bodies.each do |body|
      assert_operator body.length, :<=, 150, body
      assert_operator body.scan(/[.!?](\s|\z)/).size, :<=, 2, body
    end
  end

  # [component] Alex, 2026-09-29: "move the special rules to below the pieces",
  # and a stat a Special Rule explains links to that rule's card by a plain
  # hash anchor, so /rules#rule-trumps works from anywhere.
  test "special rules follow the units, and each explained stat links to its rule" do
    get rules_path

    ids = css_select("article.rules-page section[id]").map { _1["id"] }
    assert_operator ids.index("units"), :<, ids.index("special-rules"), "Units before Special Rules"
    assert_equal ids.index("special-rules") + 1, ids.index("rule-changes")
    assert_equal %w[rule-range rule-cavalry rule-dragon rule-trumps], css_select("#special-rules .special-rule-card").map { _1["id"] }

    links = ->(selector) { css_select(selector).map { [ _1["href"], _1["aria-label"] ] } }
    assert_equal [ [ "#rule-range", "Range 2 — see the Range Units rule" ], [ "#rule-range", "Range 3 — see the Range Units rule" ],
                   [ "#rule-range", "Range 4 — see the Range Units rule" ] ],
                 links.call("#units dd[data-stat=range] a")
    assert_equal [ [ "#rule-cavalry", "Movement 4 + 1 — see the Cavalry Units rule" ],
                   [ "#rule-cavalry", "Movement 3 + 1 — see the Cavalry Units rule" ] ],
                 links.call("#class-cavalry dd[data-stat=movement] a")
    assert_equal [ [ "#rule-dragon", "Movement: moves any distance in a straight line — see the Your Dragon rule" ] ],
                 links.call("#unit-dragon dd[data-stat=movement] a")
    trumps = css_select("#units dd[data-stat=trump] a")
    assert_equal 4, trumps.size, "Rabble, Catapult, Trebuchet and King each trump one piece"
    trumps.each do |a|
      assert_equal "#rule-trumps", a["href"]
      alt = a.at_css("img.unit-trump-icon")["alt"]
      assert_match(/\ATrumps (King|Dragon)\z/, alt, "the icon keeps its name")
      assert_equal "#{alt} — see the Trumps rule", a["aria-label"]
    end
    # Every link lands on a card that exists; numbers that no rule explains stay plain.
    css_select("#units a[href^='#rule-']").each { |a| assert_select a["href"], 1 }
    assert_select "#units dd[data-stat=strength] a", 0
    assert_select "#class-vanguard dd[data-stat=movement] a, #unit-king dd[data-stat=movement] a, #unit-mountain dd a", 0
    assert_select "#special-rules a[href^='#rule-']", 0, "a rule card does not link to itself"
    assert_select "article.rules-page[data-controller=rule-links]"
  end

  # Alex, September 29, 2026 (cyvasse-stats-and-trumps-v3): trumps work on
  # offense only, range units defend at 1, and the change is listed.
  test "rules states offense-only trumps and the new stats" do
    get rules_path

    assert_select "#special-rules .special-rule-card[data-rule=trump] p", text: /Trumps work on attack only: a Rabble that attacks a King wins/
    assert_select "#special-rules .special-rule-card[data-rule=range] p", text: /move or shoot, never both\. They defend at Strength 1\./
    assert_select "#special-rules .special-rule-card[data-rule=dragon] p", text: /Taking a Range unit ends its flight/
    assert_select "#combat p", text: /Range\s+units defend at Strength 1/
    assert_select "#combat p", text: /unless a Trump is involved/, count: 0
    assert_select "#rule-changes #changes-2026 li", text: /Trumps now work on offense only/
    assert_select "#rule-changes #changes-2026 li", text: /Catapults now move 1/
    assert_select "#unit-catapult dd", text: "1"
    assert_select "#unit-spearman dd", text: "3"
    assert_select "#unit-elephant dd", text: "4"
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
