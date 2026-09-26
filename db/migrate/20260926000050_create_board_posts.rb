# The old public message board (epic cyvasse-revival piece 15). The legacy
# app stored a board post as a messages row with receiver 0 and match 0 and
# listed them at /message_board (home#message_board: Message.where(match: 0)).
# Alex: the board is admin only now; nobody posts to it.
#
# A table of its own rather than messages with a nullable receiver: every
# private-message rule (Message.visible_to, involving, between, the inbox and
# the admin Conversations grouping by the sender/receiver pair, the
# receiver_id NOT NULL foreign key) assumes two people, and a board post has
# one. Kept apart, no private-message query can ever return a board post.
#
# The legacy columns come over as they were: message (text, a superset of
# varchar(255)), sender -> user_id through users.legacy_id, created_at and
# updated_at. receiver and match were always 0 and read always false, so
# they are dropped. legacy_id holds the legacy messages.id, unique, so a
# rerun of the import skips rows it already brought over.
class CreateBoardPosts < ActiveRecord::Migration[8.1]
  def change
    create_table :board_posts do |t|
      t.text :message
      t.references :user, null: false, foreign_key: true
      t.integer :legacy_id

      t.timestamps
    end

    add_index :board_posts, :legacy_id, unique: true
    add_index :board_posts, [ :created_at, :id ]
  end
end
