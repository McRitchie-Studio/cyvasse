class User < ApplicationRecord
  include Sluggable

  # The engine's signed-in user nav renders components/avatar, which needs the
  # avatar attachment plus avatar_initials and avatar_color (the house pattern
  # shared with mcritchie-studio and mcritchie-industries).
  has_one_attached :avatar

  # A public name for online play (epic piece 6): how players find and
  # challenge each other. 3-20 letters, digits or underscores, unique in any
  # case. Checked only when it changes, so a legacy name imported by piece 10
  # never blocks an unrelated save.
  USERNAME_FORMAT = /\A[A-Za-z0-9_]{3,20}\z/
  validates :username, format: { with: USERNAME_FORMAT, message: "is 3 to 20 letters, digits or underscores" },
                       if: :will_save_change_to_username?
  validate :username_free_in_any_case, if: :will_save_change_to_username?

  has_many :home_matches, class_name: "Match", foreign_key: :home_user_id, inverse_of: :home_user, dependent: :restrict_with_error
  has_many :away_matches, class_name: "Match", foreign_key: :away_user_id, inverse_of: :away_user, dependent: :restrict_with_error
  # Messages (piece 12). A player with messages is kept, like one with matches.
  has_many :sent_messages, class_name: "Message", foreign_key: :sender_id, inverse_of: :sender, dependent: :restrict_with_error
  has_many :received_messages, class_name: "Message", foreign_key: :receiver_id, inverse_of: :receiver, dependent: :restrict_with_error

  # The piece art this player chose (PieceSkinPreference); nil until they do.
  validates :piece_skin, inclusion: { in: Piece::SKINS.keys.map(&:to_s) }, allow_nil: true

  AVATAR_COLORS = %w[#EF4444 #F97316 #EAB308 #22C55E #06B6D4 #3B82F6 #8B5CF6 #EC4899].freeze

  # The seeded identities (studio-engine/docs/NEW_APP_SETUP.md section 11):
  # the shared operator, the ordinary member, and an admin on this app's own
  # domain. Names must parameterize to DISTINCT slugs — Sluggable derives the
  # uniquely indexed slug from the name.
  SEED_IDENTITIES = [
    { email: "alex@mcritchie.studio", name: "Alex McRitchie", role: "admin" },
    # The member is not optional: without one every seeded account is an admin
    # and nothing can be looked at as an ordinary player.
    { email: "mack@mcritchie.studio", name: "Mack McRitchie", role: "viewer" },
    { email: "alex@cyvasse.mcritchie.studio", name: "Alex McRitchie (Cyvasse)", role: "admin" }
  ].freeze

  def name_slug
    name.present? ? name.parameterize : "user-#{id}"
  end

  # A legacy player (LegacyImport) has a username and no name.
  def display_name
    name.presence || username.presence || email&.split("@")&.first || "User"
  end

  def avatar_initials
    display_name.first.upcase
  end

  def avatar_color
    key = name.presence || email.presence || id.to_s
    AVATAR_COLORS[Digest::MD5.hexdigest(key).hex % AVATAR_COLORS.size]
  end

  # Case-insensitive, through the lower(username) index.
  def self.find_by_username(name)
    return nil if name.blank?

    where("lower(username) = ?", name.to_s.strip.downcase).first
  end

  def matches
    Match.involving(self)
  end

  def admin?
    role == "admin"
  end

  # The name shown beside a message: the public username, or for an account
  # that never chose one, its display name.
  def player_name
    username.presence || display_name
  end

  def unread_messages_count
    Message.unread_by(self).count
  end

  # Idempotent: creates any missing identity, never overwrites an existing row.
  def self.seed_identities!
    SEED_IDENTITIES.map do |attrs|
      find_or_create_by!(email: attrs[:email]) do |user|
        user.name = attrs[:name]
        user.role = attrs[:role]
      end
    end
  end

  private

  def username_free_in_any_case
    return if username.blank?

    taken = User.where("lower(username) = ?", username.downcase).where.not(id: id).exists?
    errors.add(:username, "is taken") if taken
  end
end
