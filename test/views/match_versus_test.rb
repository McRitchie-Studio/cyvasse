require "test_helper"

# [component] The match's versus card (matches/_versus, players/_avatar):
# you over them, each an avatar then a name, a vs between, a person's photo or else their
# own piece art in their colour, a computer player's seeded portrait
# (users.portrait, app/assets/images/bots) when it has one and its piece art on
# the computer accent when not.
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

  test "a computer player with no portrait shows its piece art" do
    assert_nil bot_portrait(@haldon)
    render_versus
    assert_select "[data-avatar=bot-fallback][role=img][aria-label='Haldon Halfmaester'] img[src*='pieces/vector/catapult']"
    assert_includes css_select("[data-avatar=bot-fallback]").sole["class"], "ring-[var(--color-cta,#8E82FE)]"
    assert_select "[data-side=them] [data-avatar=piece]", 0
    assert_select "[data-avatar=bot-portrait]", 0
  end

  test "a computer player shows the portrait its seed set, from the real asset" do
    User.seed_computer_player!("haldon")
    @haldon.reload
    assert_equal "bots/haldon.webp", bot_portrait(@haldon)
    render_versus
    assert_select "[data-side=them] img[data-avatar=bot-portrait][alt='Haldon Halfmaester'][src*='bots/haldon-'][src$='.webp']"
    assert_includes css_select("[data-avatar=bot-portrait]").sole["class"], "rounded-full"
    assert_select "[data-avatar=bot-fallback]", 0
  end

  test "a portrait only by filename does not count: the seed is the source of truth" do
    assert Rails.application.assets.load_path.find("bots/haldon.webp"), "the file is there"
    assert_nil @haldon.portrait
    render_versus
    assert_select "[data-avatar=bot-fallback]"
  end

  test "a portrait whose file is missing, or an unsafe path, falls back to piece art" do
    @haldon.update_columns(portrait: "bots/nobody.webp")
    assert_nil bot_portrait(@haldon)
    @haldon.update_columns(portrait: "../secrets.webp")
    assert_nil bot_portrait(@haldon)
    render_versus
    assert_select "[data-avatar=bot-fallback] img[src*='pieces/vector/catapult']"
  end

  test "a computer player with no named portrait (legacy ids 8-10) keeps the default piece" do
    alexx = User.create!(legacy_id: 8, username: "alexx")
    render_versus(opponent: alexx, name: "alexx")
    assert_select "[data-avatar=bot-fallback] img[src*='pieces/vector/#{AvatarsHelper::BOT_DEFAULT_PIECE}']"
  end
end
