# The game board: one game of Cyvasse against the computer, in the browser.
#
# Public on purpose. The legacy "play the computer" match needed an account
# only to be saved; this one is played entirely client-side (the engine is
# app/javascript/cyvasse) and nothing is stored, so there is nothing for a
# sign-in to protect. Matches and accounts arrive with epic piece 6.
class GamesController < ApplicationController
  skip_before_action :require_authentication

  DEFAULT_SKIN = :vector

  def show
    @skin = skin
    @piece_images = Piece.all.to_h { |piece| [ piece.slug, helpers.image_path(piece.image(@skin)) ] }
  end

  private

  # The piece art is one parameter: `?skin=pencil` draws the pencil skin. The
  # skin switcher (piece 5) only has to choose this value.
  def skin
    requested = params[:skin].to_s.to_sym
    Piece::SKINS.key?(requested) ? requested : DEFAULT_SKIN
  end
end
