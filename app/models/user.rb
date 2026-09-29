class User < ApplicationRecord
  include Sluggable
  # onboarding_missing and onboarding_due?: what an incomplete account lacks.
  include User::Onboarding

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
  # Posts on the old public message board (piece 15), kept like messages.
  has_many :board_posts, dependent: :restrict_with_error
  # Saved army lineups (piece 10b), three slots; they go with the player.
  has_many :setups, dependent: :delete_all
  has_many :live_seeks, dependent: :delete_all
  # The account that absorbed this guest (GuestClaim), when the guest was kept.
  belongs_to :merged_into, class_name: "User", optional: true

  # Guests GuestClaim may still absorb: not yet merged into an account.
  scope :claimable_guests, -> { where(guest: true, merged_into_id: nil) }

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

  # The legacy app's computer opponents (legacy ids 2-10) came over with the
  # import (LegacyImport) so their old matches keep both players; nobody can
  # challenge them now. The computer lives on /play.
  COMPUTER_LEGACY_IDS = (2..10)

  def computer?
    legacy_id.present? && COMPUTER_LEGACY_IDS.cover?(legacy_id)
  end

  # The named computer players' portraits, from the old Cyvasse app
  # (amcritchie/Cyvasse app/assets/images, task cyvasse-bot-portraits): the
  # logical asset path the seed writes to users.portrait, which
  # AvatarsHelper#bot_portrait reads. A computer player missing here (legacy
  # ids 8-10) keeps its piece art.
  COMPUTER_PORTRAITS = LiveMatch::COMPUTER_NAMES.keys.index_with { |username| "bots/#{username}.webp" }.freeze
  PORTRAIT_FORMAT = %r{\Abots/[a-z0-9_]+\.(webp|png|jpg|svg)\z}
  validates :portrait, format: { with: PORTRAIT_FORMAT }, allow_nil: true

  # One named computer player (LiveMatch::COMPUTER_NAMES), found by its legacy
  # id or created (a new database has no legacy import), with its portrait set.
  # Idempotent: a second run finds the same row and writes nothing, and an
  # existing row (production's imported computer players) is updated in place.
  def self.seed_computer_player!(username)
    legacy_id = LiveMatch::COMPUTER_LEGACY_IDS.fetch(username)
    user = find_by(legacy_id:) || create!(legacy_id:, username:, name: LiveMatch::COMPUTER_NAMES.fetch(username))
    portrait = COMPUTER_PORTRAITS[username]
    user.update!(portrait:) unless user.portrait == portrait
    user
  end

  # Every named computer player, seeded (db/seeds.rb and the
  # users:seed_computer_players post-deploy task).
  def self.seed_computer_players!
    transaction { LiveMatch::COMPUTER_NAMES.keys.map { |username| seed_computer_player!(username) } }
  end

  # People with a name on the board (Leaderboard): never a computer player,
  # never a Play Now guest, and never an account with no public username (the
  # board shows usernames only, so it cannot leak a name or an email).
  scope :ranked_players, lambda {
    where(guest: false).where.not(username: [ nil, "" ])
      .where("users.legacy_id IS NULL OR users.legacy_id NOT BETWEEN ? AND ?",
             COMPUTER_LEGACY_IDS.first, COMPUTER_LEGACY_IDS.last)
  }

  def admin?
    role == "admin"
  end

  # Play Now without an account (task play-now-matchmaking): a guest player
  # with a temporary name like Guest_4821, signed in by the session alone.
  # Signing in later moves its games to that account (GuestClaim).
  def self.create_guest!(rng: Random.new)
    5.times do
      number = rng.rand(1000..9999)
      username = "Guest_#{number}"
      next if find_by_username(username)

      return create!(guest: true, username:, name: "Guest #{number}")
    rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid
      next
    end
    raise "no free guest name"
  end

  # Google sign-in (the engine's OmniauthCallbacksController), as the hub does
  # it: the account already linked to this Google identity, else the account
  # with its email once Google has verified that email (an unverified one
  # could take over someone else's account), else a new account. A name
  # another player already slugs to is left off; Sluggable's slug is unique.
  # Returns :email_not_verified for the refused link.
  def self.from_omniauth(auth, email_verified: false)
    user = find_by(provider: auth.provider, uid: auth.uid)
    return user if user

    email = auth.info.email.to_s.strip.downcase.presence
    if email && (existing = find_by(email:))
      return :email_not_verified unless email_verified

      existing.update!(provider: auth.provider, uid: auth.uid)
      return existing
    end

    name = auth.info.name.presence
    name = nil if name && exists?(slug: name.parameterize)
    create!(email:, name:, provider: auth.provider, uid: auth.uid)
  rescue ActiveRecord::RecordNotUnique
    # A concurrent callback created it first.
    find_by(provider: auth.provider, uid: auth.uid) || (email && find_by(email:))
  end

  # The name shown beside a message: the public username, or for an account
  # that never chose one, its display name.
  def player_name
    username.presence || display_name
  end

  def unread_messages_count
    Message.with_text.unread_by(self).count
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
