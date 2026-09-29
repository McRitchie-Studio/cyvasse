# Player avatars (players/_avatar). A person shows their uploaded picture,
# else their own piece of the vector art ringed in their colour. A computer player shows the portrait
# its seed set (users.portrait, an app/assets/images/bots path: the old Cyvasse
# app's pictures), else its own piece of the game's vector art on the computer
# accent.
module AvatarsHelper
  # One piece per computer player (LiveMatch::COMPUTER_NAMES keys).
  BOT_PIECES = {
    "qavo" => "trebuchet", "tyrion" => "crossbowman", "haldon" => "catapult",
    "doran" => "spearman", "ben" => "heavyhorse", "aegon" => "dragon"
  }.freeze
  BOT_DEFAULT_PIECE = "elephant".freeze

  # A person's default: every piece but the mountain (terrain).
  USER_PIECES = Piece.all.reject { |piece| piece.slug == "mountain" }.freeze

  # The logical asset path of a computer player's portrait, or nil. The seed
  # is the source of truth (users.portrait, User.seed_computer_players!); a
  # path whose file is missing falls back to piece art rather than a 500.
  def bot_portrait(user)
    path = user.portrait.presence
    return nil unless path&.match?(User::PORTRAIT_FORMAT)

    path if Rails.application.assets.load_path.find(path)
  end

  def bot_piece(user)
    Piece.all.find { |piece| piece.slug == BOT_PIECES.fetch(user.username.to_s.downcase, BOT_DEFAULT_PIECE) }
  end

  # Stable per user: the same piece on every page and in every game.
  def user_piece(user)
    USER_PIECES[Digest::MD5.hexdigest("piece-#{user.id}").hex % USER_PIECES.size]
  end
end
