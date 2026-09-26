# The old public message board (epic cyvasse-revival piece 15; Alex: "public
# message board admin only"). Read-only: every legacy post with text, newest
# first, a page at a time. Blank posts are counted, never shown. Admins only
# (Admin::BaseController); no player-facing page shows a board post.
module Admin
  class MessageBoardController < BaseController
    def index
      @page = BoardPost.page(params[:page])
      @blank = BoardPost.blank_text.count
    end
  end
end
