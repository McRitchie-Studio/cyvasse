# Player avatars (players/_avatar). A person shows their uploaded picture,
# else the initials bubble. A computer player shows its portrait from
# app/assets/images/bots/<username>.<ext> when one is there, else its own piece
# of the game's vector art on the computer accent. The fallback is the game's
# art on purpose: never a likeness of the characters the bots are named after.
module AvatarsHelper
  BOT_PORTRAIT_EXTENSIONS = %w[webp png jpg svg].freeze

  # One piece per computer player (LiveMatch::COMPUTER_NAMES keys).
  BOT_PIECES = {
    "qavo" => "trebuchet", "tyrion" => "crossbowman", "haldon" => "catapult",
    "doran" => "spearman", "ben" => "heavyhorse", "aegon" => "dragon"
  }.freeze
  BOT_DEFAULT_PIECE = "elephant".freeze

  # The logical asset path of a computer player's portrait, or nil.
  def bot_portrait(user)
    key = user.username.to_s.downcase
    return nil unless key.match?(/\A[a-z0-9_]+\z/)

    BOT_PORTRAIT_EXTENSIONS.map { |ext| "bots/#{key}.#{ext}" }
                           .find { |path| Rails.application.assets.load_path.find(path) }
  end

  def bot_piece(user)
    Piece.all.find { |piece| piece.slug == BOT_PIECES.fetch(user.username.to_s.downcase, BOT_DEFAULT_PIECE) }
  end
end
