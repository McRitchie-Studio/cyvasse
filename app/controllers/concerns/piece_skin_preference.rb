# Which piece art a request draws: the pencil drawings or the vector art
# (epic cyvasse-revival piece 5).
#
# The answer, first match wins:
#   1. `?skin=` on the URL — a one-off look, never saved
#   2. the signed-in player's `users.piece_skin`
#   3. the `cyvasse_skin` cookie, which carries a signed-out player's choice
#   4. vector, the default
#
# Only SkinsController#update writes a choice; everything else only reads.
module PieceSkinPreference
  extend ActiveSupport::Concern

  COOKIE = :cyvasse_skin
  DEFAULT = :vector

  included do
    helper_method :current_skin
  end

  # Symbol, always one of Piece::SKINS' keys.
  def current_skin
    @current_skin ||= [ params[:skin], current_user&.piece_skin, cookies[COOKIE] ]
      .map { |value| PieceSkinPreference.normalize(value) }
      .compact.first || DEFAULT
  end

  # The skin named by `value`, or nil when it names no skin.
  def self.normalize(value)
    skin = value.to_s.to_sym
    Piece::SKINS.key?(skin) ? skin : nil
  end

  private

  def remember_skin!(skin)
    cookies.permanent[COOKIE] = { value: skin.to_s, httponly: true, same_site: :lax }
    current_user&.update!(piece_skin: skin.to_s)
    @current_skin = skin
  end
end
