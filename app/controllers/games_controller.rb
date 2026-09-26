# The game board: one game of Cyvasse against the computer, in the browser.
#
# Public on purpose. The legacy "play the computer" match needed an account
# only to be saved; this one is played entirely client-side (the engine is
# app/javascript/cyvasse) and nothing is stored, so there is nothing for a
# sign-in to protect. Matches and accounts arrive with epic piece 6.
class GamesController < ApplicationController
  skip_before_action :require_authentication

  def show
    @skin = current_skin
    # Both skins' art, so the switcher can redraw a game in progress without
    # a reload; the board starts on @skin.
    @skin_images = Piece::SKINS.keys.to_h do |skin|
      [ skin, Piece.all.to_h { |piece| [ piece.slug, helpers.image_path(piece.image(skin)) ] } ]
    end
    @piece_images = @skin_images.fetch(@skin)
  end
end
