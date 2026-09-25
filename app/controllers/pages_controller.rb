class PagesController < ApplicationController
  # The public pages: the front door and the piece gallery. The game itself
  # (epic piece 4) decides its own gate.
  skip_before_action :require_authentication

  def index
  end

  def pieces
    @pieces = Piece.all
  end
end
