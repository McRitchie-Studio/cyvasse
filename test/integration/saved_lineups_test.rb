require "test_helper"

# [integration] Saved lineups on the pages (piece 10b): the setup panel of
# /play and of a match draws the player's slots, POST /lineups saves one, and
# only a signed-in player can.
class SavedLineupsTest < ActionDispatch::IntegrationTest
  setup do
    @arya = User.create!(email: "arya@example.com", name: "Arya", username: "arya")
    @brienne = User.create!(email: "brienne@example.com", name: "Brienne", username: "brienne")
  end

  test "a visitor to /play is offered sign-in, not the slots, and cannot save" do
    get play_path
    assert_response :success
    assert_select "[data-controller=cyvasse-setups]", count: 0
    assert_select "a[href=?]", signin_path, text: "Sign in"

    post setups_path, params: { slot: 1, name: "Wall", lineup: army(52..70) }, as: :json
    assert_response :unauthorized
    assert_equal 0, Setup.count
  end

  test "a signed-in player's /play panel draws each slot, and a lineup that cannot be placed is disabled" do
    Setup.create!(user: @arya, button_position: 1, name: "Shield Wall", units_position: army(52..70))
    Setup.insert_all!([ { user_id: @arya.id, button_position: 3, name: "Broken", units_position: army(52..69),
                          created_at: Time.current, updated_at: Time.current } ])
    log_in_as(@arya)
    get play_path

    assert_select "[data-controller=cyvasse-setups][data-action*='cyvasse-setups:load->cyvasse-game#loadLineup']"
    assert_select "[data-slot='1'] button[data-slot-load][data-lineup=?]:not([disabled])", army(52..70), text: "Shield Wall"
    assert_select "[data-slot='2'] button[data-slot-load][disabled]", text: "Empty slot 2"
    assert_select "[data-slot='3'] button[data-slot-load][disabled]", text: "Broken"
  end

  test "a match in setup offers the player's slots to the match board" do
    Setup.create!(user: @arya, button_position: 2, name: "Hammer", units_position: army(73..91))
    match = Match.challenge!(@arya, "brienne")
    log_in_as(@arya)
    get match_path(match)

    assert_select "[data-controller=cyvasse-setups][data-action*='cyvasse-setups:load->cyvasse-match#loadLineup']"
    assert_select "[data-slot='2'] button[data-slot-load][data-lineup=?]", army(73..91), text: "Hammer"
  end

  test "saving replaces the slot and answers every slot" do
    Setup.create!(user: @arya, button_position: 1, name: "Old", units_position: army(52..70))
    log_in_as(@arya)
    post setups_path, params: { slot: 1, name: " New ", lineup: army(73..91) }, as: :json

    assert_response :success
    assert_equal [ "New" ], @arya.setups.pluck(:name)
    slots = response.parsed_body["slots"]
    assert_equal [ 1, 2, 3 ], slots.map { |s| s["slot"] }
    assert_equal({ "slot" => 1, "name" => "New", "lineup" => army(73..91) }, slots.first)
    assert_equal({ "slot" => 2, "name" => "", "lineup" => nil }, slots.second)
  end

  test "a save that will not do is refused with the reason and changes nothing" do
    Setup.create!(user: @arya, button_position: 1, name: "Old", units_position: army(52..70))
    log_in_as(@arya)

    post setups_path, params: { slot: 1, name: "Bad", lineup: army(1..19) }, as: :json
    assert_response :unprocessable_entity
    assert_match(/five rows/, response.parsed_body["error"])
    assert_equal "Old", response.parsed_body["slots"].first["name"]

    post setups_path, params: { slot: 9, name: "Bad", lineup: army(52..70) }, as: :json
    assert_response :unprocessable_entity
    post setups_path, params: { slot: 1, name: "", lineup: army(52..70) }, as: :json
    assert_response :unprocessable_entity
    assert_equal [ "Old" ], @arya.setups.pluck(:name)
  end

  test "a player saves only to their own slots" do
    Setup.create!(user: @brienne, button_position: 1, name: "Hers", units_position: army(52..70))
    log_in_as(@arya)
    post setups_path, params: { slot: 1, name: "Mine", lineup: army(73..91), user_id: @brienne.id }, as: :json

    assert_response :success
    assert_equal [ "Hers" ], @brienne.setups.pluck(:name)
    assert_equal [ "Mine" ], @arya.setups.pluck(:name)
  end

  private

  def army(hexes) = hexes.to_a.each_with_index.map { |hex, i| "#{i + 1}:#{hex}|" }.join
end
