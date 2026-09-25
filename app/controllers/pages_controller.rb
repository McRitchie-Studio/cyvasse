class PagesController < ApplicationController
  # The public pages: the front door, the piece gallery, the rules and about. The game itself
  # (epic piece 4) decides its own gate.
  skip_before_action :require_authentication

  def index
  end

  def pieces
    @pieces = Piece.all
  end

  def rules
    @unit_classes = Rulebook.classes
  end

  def about
  end
end
