class PagesController < ApplicationController
  # The landing page is the public front door, and the ONLY public surface the
  # app defines so far. The game itself (epic piece 4) decides its own gate.
  skip_before_action :require_authentication

  def index
  end
end
