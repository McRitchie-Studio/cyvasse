class PagesController < ApplicationController
  # The public pages: the front door, the piece gallery, the rules and about. The game itself
  # (epic piece 4) decides its own gate.
  skip_before_action :require_authentication

  def index
    # Back from Google sign-in (ApplicationController#remember_google_return).
    if (path = session.delete(AFTER_SIGN_IN)) && current_user && !current_user.guest?
      flash.keep
      return redirect_to(path)
    end

    # The top ten under Play Now (Leaderboard: the live board's rule).
    @live_leaderboard = Leaderboard.live
    # The background slides, from a random piece (HomeGallery).
    @gallery = HomeGallery.slides
  end

  def pieces
    @pieces = Piece.all
    # Both skins stay on show; the one in use comes first.
    @skins = [ current_skin, *(Piece::SKINS.keys - [ current_skin ]) ]
  end

  def rules
    @unit_classes = Rulebook.classes
  end

  def about
  end
end
