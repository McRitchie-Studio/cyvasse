# One message from one player to another (epic cyvasse-revival piece 12),
# stored in the legacy messages columns (see the CreateMessages migration for
# the mapping) so the legacy history can be imported as is.
#
# A message is sent in a match's chat (match_id set) or as a reply in the
# inbox (match_id null, as legacy messages sent from a profile were). Either
# way it belongs to the conversation between its two people: every message
# between them, in any match or none (Conversation).
#
# Who may read one: its sender, its receiver, and an admin. The About page
# says so. Who may SEND one: User#can_message? (task cyvasse-live-chat),
# checked here on every new message, so no way in skips it.
#
# Every new message is broadcast live once committed (ChatBroadcasts): to the
# pair's thread, and to each person's Chat hub and unread badge.
class Message < ApplicationRecord
  MAX_LENGTH = 1000
  NOT_ALLOWED = "You can message only players you have played.".freeze

  belongs_to :sender, class_name: "User"
  belongs_to :receiver, class_name: "User"
  belongs_to :match, optional: true

  # Checked on new messages only: legacy rows may be blank, and the importer
  # writes them without these rules.
  validates :message, presence: true, length: { maximum: MAX_LENGTH }, on: :create
  validate :two_different_people, on: :create
  validate :sent_between_the_match_players, on: :create
  validate :sender_may_message_receiver, on: :create, unless: :legacy_id?

  after_create_commit { ChatBroadcasts.message_created(self) }

  # Hide the blank ones (empty or whitespace-only text; 10,778 legacy rows)
  # everywhere a message is shown or counted: the match chat, the inbox, the
  # unread count and the admin pages. They stay in the table, as imported.
  scope :with_text, -> { where(text_present_sql(table_name)) }
  scope :chronological, -> { order(:created_at, :id) }
  scope :involving, ->(user) { where(sender_id: user.id).or(where(receiver_id: user.id)) }
  scope :between, lambda { |one, other|
    where(sender_id: one.id, receiver_id: other.id).or(where(sender_id: other.id, receiver_id: one.id))
  }
  # The same messages as `between`, addressed by the pair's user ids (low,
  # high) the way index_messages_on_conversation is keyed, so a long legacy
  # thread is read through that index.
  scope :in_pair, lambda { |low_id, high_id|
    where("#{Conversation::PAIR_LOW} = ? AND #{Conversation::PAIR_HIGH} = ?", *[ low_id, high_id ].minmax)
  }
  scope :unread_by, ->(user) { where(receiver_id: user.id, read: false) }
  # Leaving out a computer player's messages: the unread badge counts people.
  scope :from_humans, -> { where.not(sender_id: User.computers.select(:id)) }
  # Only conversations between two people: the Chat hub lists no computer.
  scope :between_humans, -> { from_humans.where.not(receiver_id: User.computers.select(:id)) }

  # SQL true when `table`.message holds a character that is not whitespace;
  # NULL (and so false in a WHERE) for a null message.
  def self.text_present_sql(table)
    "#{connection.quote_table_name(table)}.message ~ '[^[:space:]]'"
  end

  # Every message `user` may read: an admin reads them all, a player only
  # their own conversations, anyone else nothing.
  def self.visible_to(user)
    return none if user.nil?

    user.admin? ? with_text : involving(user).with_text
  end

  # Send `text` from `sender` to their opponent in `match`'s chat.
  def self.post_in_match!(match, sender, text)
    raise Match::Refused, "You are not playing in this match." unless match.player?(sender)

    create!(match: match, sender: sender, receiver: match.opponent_of(sender), message: text.to_s.strip)
  end

  # Send `text` from `sender` to `receiver` outside any match: a reply or a
  # first message from the Chat hub. Raises ActiveRecord::RecordInvalid when
  # refused (blank, too long, or someone the sender may not message).
  def self.send_direct!(sender, receiver, text)
    create!(sender: sender, receiver: receiver, message: text.to_s.strip)
  end

  # Mark every message in `scope` addressed to `reader` as read. Returns the
  # number marked; when any were, the reader's badge (and, given `other`,
  # their hub row for that conversation) updates live.
  def self.mark_read!(scope, reader, other: nil)
    marked = scope.unread_by(reader).update_all(read: true, updated_at: Time.current)
    ChatBroadcasts.read(reader, other) if marked.positive?
    marked
  end

  def readable_by?(user)
    user.present? && (user.admin? || participant?(user))
  end

  def participant?(user)
    user.present? && [ sender_id, receiver_id ].include?(user.id)
  end

  private

  def two_different_people
    errors.add(:receiver, "must be someone else") if sender_id.present? && sender_id == receiver_id
  end

  def sender_may_message_receiver
    return if sender.nil? || receiver.nil? || sender.can_message?(receiver, match:)

    errors.add(:base, NOT_ALLOWED)
  end

  def sent_between_the_match_players
    return if match.nil? || (match.player?(sender) && match.player?(receiver))

    errors.add(:match, "is not between these two players")
  end
end
