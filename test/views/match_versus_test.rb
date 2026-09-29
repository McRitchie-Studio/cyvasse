require "test_helper"

# [component] The match header's versus line (matches/_versus, players/_avatar):
# an avatar at each outer edge around the vs, a person's photo or initials, a
# computer player's portrait from app/assets/images/bots when one is there and
# its piece art on the computer accent when not.
class MatchVersusTest < ActionView::TestCase
  helper AvatarsHelper

  setup do
    @arya = User.create!(email: "arya@example.test", name: "Arya", username: "arya")
    @haldon = User.create!(legacy_id: 4, username: "haldon", name: "Haldon Halfmaester")
  end

  def render_versus(me: @arya, opponent: @haldon, name: "Haldon Halfmaester")
    render partial: "matches/versus", locals: { me:, opponent:, opponent_name: name }
  end

  test "reads avatar, name, vs, name, avatar" do
    render_versus
    order = css_select("h1.match-versus [data-avatar], h1.match-versus .match-versus-name, h1.match-versus .match-versus-vs")
              .map { |n| n["data-avatar"] ? "avatar" : n.text.squish }
    assert_equal [ "avatar", "arya", "vs", "Haldon Halfmaester computer", "avatar" ], order
    assert_select "[data-side=me] > :first-child[data-avatar=initials]"
    assert_select "[data-side=them] > :last-child[data-avatar=bot-fallback]"
    assert_select "[data-side=them] [data-cyvasse-match-target=opponent]", "Haldon Halfmaester"
    assert_select ".live-computer-tag", "computer"
  end

  test "a person with no photo gets their initials in their colour" do
    render_versus(opponent: User.create!(email: "bran@example.test", name: "Bran", username: "bran"), name: "bran")
    assert_select "[data-side=me] [data-avatar=initials][aria-label=arya]", "A"
    assert_includes css_select("[data-side=me] [data-avatar=initials]").first["style"], @arya.avatar_color
    assert_select "[data-side=them] [data-avatar=initials]", "B"
    assert_select ".live-computer-tag", 0
  end

  test "a person with a photo shows it" do
    @arya.avatar.attach(io: File.open(Rails.root.join("app/assets/images/hex.svg")), filename: "me.svg", content_type: "image/svg+xml")
    render_versus
    assert_select "[data-side=me] img[data-avatar=photo][alt=arya]"
    assert_select "[data-side=me] [data-avatar=initials]", 0
  end

  test "a computer player with no portrait shows its piece art, never a likeness" do
    assert_nil bot_portrait(@haldon)
    render_versus
    assert_select "[data-avatar=bot-fallback][role=img][aria-label='Haldon Halfmaester'] img[src*='pieces/vector/catapult']"
  end

  test "a computer player's portrait is used as soon as bots/<username> exists" do
    Dir.mktmpdir do |dir|
      file = Pathname(dir).join("haldon.webp").tap { |f| f.write("portrait") }
      load_path = Rails.application.assets.load_path
      asset = Propshaft::Asset.new(file, logical_path: Pathname("bots/haldon.webp"), load_path:)
      load_path.singleton_class.alias_method(:find_without_portrait, :find)
      load_path.define_singleton_method(:find) { |path| path == "bots/haldon.webp" ? asset : find_without_portrait(path) }
      begin
        assert_equal "bots/haldon.webp", bot_portrait(@haldon)
        render_versus
      ensure
        load_path.singleton_class.send(:remove_method, :find)
      end
    end
    assert_select "[data-side=them] img[data-avatar=bot-portrait][alt='Haldon Halfmaester'][src*='bots/haldon-']"
    assert_select "[data-avatar=bot-fallback]", 0
  end
end
