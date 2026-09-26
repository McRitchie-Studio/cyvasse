require "test_helper"

# [component] The piece-skin switcher (epic cyvasse-revival piece 5): the
# toggle on /play, /pieces and /rules, PATCH /skin, and where the choice is
# remembered — the cyvasse_skin cookie when signed out, users.piece_skin
# when signed in. Resolution order lives in PieceSkinPreference.
class SkinSwitcherTest < ActionDispatch::IntegrationTest
  PAGES = { play: "/play", pieces: "/pieces", rules: "/rules" }.freeze

  def board_skin
    css_select("[data-controller=cyvasse-game]").first["data-cyvasse-game-skin-value"]
  end

  def rules_art_skins
    css_select("#units figure.piece-tile img").map { |img| img["src"][%r{/pieces/(\w+)/}, 1] }.uniq
  end

  def pieces_lead_skin
    css_select("section#king figure.piece-tile").first["data-skin"]
  end

  def pressed_skin
    pressed = css_select(".skin-toggle button[aria-pressed=true]")
    assert_equal 1, pressed.size, "exactly one skin is pressed"
    pressed.first["data-skin"]
  end

  def member
    @member ||= User.create!(email: "player@example.com", name: "Skin Player")
  end

  def choose(skin, return_to: "/play", **options)
    patch skin_path, params: { skin: skin, return_to: return_to }, **options
  end

  test "every page shows the toggle, vector pressed by default" do
    PAGES.each_value do |path|
      get path
      assert_select ".skin-toggle form[action=?]", skin_path, count: 2
      assert_select ".skin-toggle input[name=_method][value=patch]", count: 2
      assert_equal "vector", pressed_skin, path
    end
  end

  test "a signed-out choice is saved in a cookie and every page honours it" do
    choose "pencil", return_to: "/rules"

    assert_redirected_to "/rules"
    assert_response :see_other
    assert_equal "pencil", cookies[:cyvasse_skin]

    get play_path
    assert_equal "pencil", board_skin
    assert_equal "pencil", pressed_skin
    get rules_path
    assert_equal [ "pencil" ], rules_art_skins
    get pieces_path
    assert_equal "pencil", pieces_lead_skin
    assert_select "[data-skin-heading]:nth-of-type(1)", text: /Pencil\s+· in use/
  end

  test "the cookie outlives the session: it is permanent and httponly" do
    choose "pencil"

    set_cookie = Array(response.headers["Set-Cookie"]).join("\n")
    assert_match(/cyvasse_skin=pencil/, set_cookie)
    assert_match(/expires=/i, set_cookie)
    assert_match(/httponly/i, set_cookie)
  end

  test "switching back to vector overwrites the cookie" do
    choose "pencil"
    choose "vector"

    assert_equal "vector", cookies[:cyvasse_skin]
    get rules_path
    assert_equal [ "vector" ], rules_art_skins
  end

  test "a signed-in choice lands on the account and follows the player to a new browser" do
    user = member
    log_in_as(user)
    choose "pencil"

    assert_equal "pencil", user.reload.piece_skin

    fresh = open_session
    token = Studio::Link.create_magic_link(email: user.email).token
    fresh.post link_consume_path(token: token)
    assert_nil fresh.cookies[:cyvasse_skin], "a new browser carries no skin cookie"
    fresh.get rules_path
    assert_equal [ "pencil" ], fresh.css_select("#units figure.piece-tile img").map { |img| img["src"][%r{/pieces/(\w+)/}, 1] }.uniq
  end

  test "the account's choice outranks a stale cookie" do
    choose "vector"
    user = member
    user.update!(piece_skin: "pencil")
    log_in_as(user)

    get play_path
    assert_equal "pencil", board_skin
  end

  test "a signed-in player who never chose falls back to the cookie" do
    choose "pencil"
    log_in_as(member)

    get play_path
    assert_equal "pencil", board_skin
  end

  test "?skin= is a one-off look and saves nothing" do
    get play_path(skin: "pencil")
    assert_equal "pencil", board_skin
    assert_nil cookies[:cyvasse_skin]

    get play_path
    assert_equal "vector", board_skin
  end

  test "?skin= overrides a saved choice for that one page" do
    choose "pencil"

    get play_path(skin: "vector")
    assert_equal "vector", board_skin
  end

  test "an unknown skin is refused and saves nothing" do
    user = member
    log_in_as(user)
    choose "chalk", return_to: "/pieces"

    assert_redirected_to "/pieces"
    assert_equal "Unknown piece skin.", flash[:alert]
    assert_nil cookies[:cyvasse_skin]
    assert_nil user.reload.piece_skin
  end

  test "JSON: the board's in-place switch gets the saved skin back, or a 422" do
    choose "pencil", as: :json
    assert_response :success
    assert_equal({ "skin" => "pencil" }, response.parsed_body)
    assert_equal "pencil", cookies[:cyvasse_skin]

    choose "chalk", as: :json
    assert_response :unprocessable_entity
    assert_equal "pencil", cookies[:cyvasse_skin]
  end

  test "return_to: back to the page, minus its query, and never off-site" do
    choose "pencil", return_to: "/play?skin=vector#board"
    assert_redirected_to "/play"

    [ "//evil.example/x", "https://evil.example", "/\\evil.example", "", "play" ].each do |target|
      choose "pencil", return_to: target
      assert_redirected_to root_path, "return_to #{target.inspect}"
    end
  end

  test "/play hands the board both skins' art so a switch needs no reload" do
    get play_path

    game = css_select("[data-controller=cyvasse-game]").first
    skins = JSON.parse(game["data-cyvasse-game-skins-value"])
    assert_equal %w[pencil vector], skins.keys.sort
    assert(skins["pencil"].values.all? { |src| src.include?("/pieces/pencil/") })
    assert_equal JSON.parse(game["data-cyvasse-game-images-value"]), skins["vector"]
    assert_select "form[data-action='submit->cyvasse-game#switchSkin'][data-skin-choice]", count: 2
  end
end
