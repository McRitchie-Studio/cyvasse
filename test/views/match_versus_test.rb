require "test_helper"

# [component] The match's versus card (matches/_versus, players/_avatar):
# you over them, each an avatar then a name, a vs between, a person's photo or else their
# own piece art in their colour, a computer player's portrait from
# app/assets/images/bots when one is there and its piece art on the computer
# accent when not.
class MatchVersusTest < ActionView::TestCase
  helper AvatarsHelper

  setup do
    @arya = User.create!(email: "arya@example.test", name: "Arya", username: "arya")
    @haldon = User.create!(legacy_id: 4, username: "haldon", name: "Haldon Halfmaester")
  end

  def render_versus(me: @arya, opponent: @haldon, name: "Haldon Halfmaester")
    render partial: "matches/versus", locals: { me:, opponent:, opponent_name: name }
  end

  test "reads avatar, name, vs, avatar, name, with a quiet Computer caption" do
    render_versus
    order = css_select("h1.match-versus [data-avatar], h1.match-versus .match-versus-name, h1.match-versus .match-versus-vs")
              .map { |n| n["data-avatar"] ? "avatar" : n.text.squish }
    assert_equal [ "avatar", "arya", "vs", "avatar", "Haldon Halfmaester" ], order
    assert_select ".match-versus-card > h1.match-versus", 1
    assert_select "[data-side=me] > :first-child[data-avatar=piece]"
    assert_select "[data-side=them] > :first-child[data-avatar=bot-fallback]"
    assert_select "[data-side=them] [data-cyvasse-match-target=opponent]", "Haldon Halfmaester"
    assert_select "[data-side=them] .match-versus-who > .match-versus-bot", "Computer"
    assert_select ".live-computer-tag", 0
  end

  test "a person with no photo gets their own piece art in their colour, not initials" do
    bran = User.create!(email: "bran@example.test", name: "Bran", username: "bran")
    render_versus(opponent: bran, name: "bran")
    [ [ "me", @arya ], [ "them", bran ] ].each do |side, user|
      disc = css_select("[data-side=#{side}] [data-avatar=piece][role=img]").sole
      assert_includes disc["style"], user.avatar_color
      assert_select disc, "img[src*='pieces/vector/#{user_piece(user).slug}']"
    end
    assert_select "[data-side=me] [data-avatar=piece][aria-label=arya]"
    assert_select "[data-avatar=initials]", 0
    assert_select ".match-versus-bot", 0
  end

  test "a person keeps the same piece every render, drawn from the lineup" do
    first = user_piece(@arya)
    assert_equal first, user_piece(User.find(@arya.id))
    assert_includes AvatarsHelper::USER_PIECES, first
    2.times { render_versus }
    assert_equal [ first.slug ] * 2,
                 css_select("[data-side=me] [data-avatar=piece] img").map { |img| img["src"][%r{pieces/vector/([a-z]+)}, 1] }
    pieces = 40.times.map { |i| user_piece(User.new(id: i + 1)) }.uniq
    assert_operator pieces.size, :>, 1, "people are spread across the pieces"
    assert_not_includes AvatarsHelper::USER_PIECES.map(&:slug), "mountain"
  end

  test "a person with a photo shows it" do
    @arya.avatar.attach(io: File.open(Rails.root.join("app/assets/images/hex.svg")), filename: "me.svg", content_type: "image/svg+xml")
    render_versus
    assert_select "[data-side=me] img[data-avatar=photo][alt=arya]"
    assert_select "[data-side=me] [data-avatar=piece]", 0
  end

  test "a computer player with no portrait shows its piece art, never a likeness" do
    assert_nil bot_portrait(@haldon)
    render_versus
    assert_select "[data-avatar=bot-fallback][role=img][aria-label='Haldon Halfmaester'] img[src*='pieces/vector/catapult']"
    assert_includes css_select("[data-avatar=bot-fallback]").sole["class"], "ring-[var(--color-cta,#8E82FE)]"
    assert_select "[data-side=them] [data-avatar=piece]", 0
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
