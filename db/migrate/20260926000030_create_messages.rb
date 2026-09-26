# Player-to-player messages (epic cyvasse-revival piece 12): the chat on each
# match, the inbox, and the admin Conversations page.
#
# The legacy messages table (amcritchie/Cyvasse db/schema.rb) was
#
#   message   string    the text
#   sender    integer   users.id of the author
#   receiver  integer   users.id of the reader
#   match     integer   matches.id, null for a message sent outside a match
#   read      boolean
#   created_at, updated_at
#
# and every one of those has a column here, so piece 10b can import the 46,976
# legacy rows one to one. Three differences, all mechanical for the importer:
#
# - sender, receiver and match are sender_id, receiver_id and match_id, real
#   foreign keys. The importer maps each legacy id to the new row through
#   users.legacy_id (and the imported match's id). A message whose sender or
#   receiver cannot be found is dropped: a conversation needs both people.
# - message is text, not varchar(255): a superset, so any legacy value fits.
# - read is NOT NULL, default false; a legacy null imports as false (unread).
#
# legacy_id holds the legacy messages.id, unique, so a re-run of the import
# skips rows it already brought over. New messages leave it null.
#
# A match can be deleted (a challenge declined or withdrawn before the first
# move); its messages stay in the conversation, with match_id nulled.
class CreateMessages < ActiveRecord::Migration[8.1]
  def change
    create_table :messages do |t|
      t.text :message
      t.references :sender, null: false, foreign_key: { to_table: :users }
      t.references :receiver, null: false, foreign_key: { to_table: :users }, index: false
      t.references :match, foreign_key: { on_delete: :nullify }, index: false
      t.boolean :read, null: false, default: false
      t.integer :legacy_id

      t.timestamps
    end

    add_index :messages, :legacy_id, unique: true
    add_index :messages, [ :match_id, :created_at ]
    add_index :messages, [ :receiver_id, :read ]
    # A conversation is the unordered pair of its two people: the inbox and
    # the admin page group and order by it.
    add_index :messages, "LEAST(sender_id, receiver_id), GREATEST(sender_id, receiver_id), created_at",
              name: "index_messages_on_conversation"
  end
end
