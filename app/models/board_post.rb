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
end
