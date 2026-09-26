# One post on the old public message board (epic cyvasse-revival piece 15),
# imported from the legacy messages table (see the CreateBoardPosts
# migration). Read-only history: nothing in the app writes one, and only
# admins read them (Admin::MessageBoardController). No player-facing page
# shows a board post.
class BoardPost < ApplicationRecord
  PER_PAGE = 50

  belongs_to :user

  # Blank posts (empty or whitespace text) are kept but never shown, as blank
  # private messages are (Message.with_text).
  scope :with_text, -> { where(Message.text_present_sql(table_name)) }
  scope :blank_text, -> { where.not(Message.text_present_sql(table_name)).or(where(message: nil)) }
  scope :newest_first, -> { order(created_at: :desc, id: :desc) }

  # One page of posts, with what messages/_pager needs.
  Page = Struct.new(:posts, :page, :total, :per_page, keyword_init: true) do
    def pages = [ (total.to_f / per_page).ceil, 1 ].max
    def next_page = page < pages ? page + 1 : nil
    def prev_page = page > 1 ? page - 1 : nil
    def first_number = total.zero? ? 0 : ((page - 1) * per_page) + 1
    def last_number = [ page * per_page, total ].min
  end

  # Page `number` of the posts with text, newest first, authors loaded.
  def self.page(number, per_page: PER_PAGE)
    number = [ number.to_i, 1 ].max
    shown = with_text
    posts = shown.newest_first.includes(:user).offset((number - 1) * per_page).limit(per_page).to_a
    Page.new(posts: posts, page: number, total: shown.count, per_page: per_page)
  end
end
