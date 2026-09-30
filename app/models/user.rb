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
  # A computer player's remote-runner tokens (BotToken); they go with it.
  has_many :bot_tokens, dependent: :delete_all
  # The account that absorbed this guest (GuestClaim), when the guest was kept.
  belongs_to :merged_into, class_name: "User", optional: true

  # The legacy computer players (COMPUTER_LEGACY_IDS), and everyone else.
  scope :computers, -> { where(legacy_id: COMPUTER_LEGACY_IDS) }
  scope :humans, -> { where(legacy_id: nil).or(where.not(legacy_id: COMPUTER_LEGACY_IDS)) }

  # Guests GuestClaim may still absorb: not yet merged into an account.
  scope :claimable_guests, -> { where(guest: true, merged_into_id: nil) }

  # The piece art this player chose (PieceSkinPreference); nil until they do.
  validates :piece_skin, inclusion: { in: Piece::SKINS.keys.map(&:to_s) }, allow_nil: true

  # The engine's components/avatar draws WHITE initials on this colour, so each
  # entry must reach WCAG AA (4.5:1) against white (task
  # cyvasse-avatar-initial-contrast). Each is the lightest Tailwind step of its
  # hue that passes: red-600, orange-700, yellow-700, green-700, cyan-700,
  # blue-600, violet-600, pink-600. A player's colour is picked by index from a
  # hash of their name, never stored, so the order and size stay fixed: change
  # a hex, never the count, or every player's colour reshuffles.
  AVATAR_COLORS = %w[#DC2626 #C2410C #A16207 #15803D #0E7490 #2563EB #7C3AED #DB2777].freeze

  # The seeded identities (studio-engine/docs/NEW_APP_SETUP.md section 11):
  # the shared operator, the ordinary member, and an admin on this app's own
  # domain. Sluggable derives each one's slug from its name (name_slug).
  SEED_IDENTITIES = [
    { email: "alex@mcritchie.studio", name: "Alex McRitchie", role: "admin" },
    # The member is not optional: without one every seeded account is an admin
    # and nothing can be looked at as an ordinary player.
    { email: "mack@mcritchie.studio", name: "Mack McRitchie", role: "viewer" },
    { email: "alex@cyvasse.mcritchie.studio", name: "Alex McRitchie (Cyvasse)", role: "admin" }
  ].freeze

  # Sluggable sets the uniquely indexed slug from this before every save. It is
  # never empty and never another account's (task cyvasse-blank-name-slug):
  #
  # 1. A slug already held stands while the name it came from does, so a legacy
  #    player's "user-<id>" and every existing slug survive an ordinary save.
  # 2. The stem is the name, transliterated (José Núñez -> jose-nunez), else
  #    the username, else nothing (a new magic-link account, or a name with no
  #    Latin letters such as "Иван" or an emoji).
  # 3. No stem: "user-" and a random token. A taken stem: the next free
  #    numeric suffix (carl, carl-2, carl-3).
  #
  # The check can lose a race with a concurrent save; create_or_update below
  # retries on the slug index rather than trusting it.
  def name_slug
    stem = slug_stem
    return slug if slug.present? && @slug_conflicts.to_i.zero? && slug_stands?(stem)
    return random_slug if stem.nil? || @slug_conflicts.to_i >= SLUG_SUFFIX_TRIES

    return stem unless slug_taken?(stem)

    "#{stem}-#{highest_slug_suffix(stem) + 1}"
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
  # could take over someone else's account), else a new account, which keeps
  # its Google name even when another player shares it (name_slug suffixes the
  # slug). Returns :email_not_verified for the refused link.
  def self.from_omniauth(auth, email_verified: false)
    user = find_by(provider: auth.provider, uid: auth.uid)
    return user if user

    email = auth.info.email.to_s.strip.downcase.presence
    if email && (existing = find_by(email:))
      return :email_not_verified unless email_verified

      existing.update!(provider: auth.provider, uid: auth.uid)
      return existing
    end

    create!(email:, name: auth.info.name.presence, provider: auth.provider, uid: auth.uid)
  rescue ActiveRecord::RecordNotUnique
    # A concurrent callback created it first.
    find_by(provider: auth.provider, uid: auth.uid) || (email && find_by(email:))
  end

  # A player's one public name, wherever a player's name renders: the navbar,
  # the Play Now splash, the versus card, the leaderboard, My games, chat and
  # messages (task cyvasse-contrast-and-names). A named computer player's full
  # name (LiveMatch::COMPUTER_NAMES), else the username as stored
  # ("Guest_4821" for a Play Now guest), else, for an account that never
  # chose one, its display name. display_name stays the engine's (a real
  # name first), for email greetings and the admin pages.
  def player_name
    (computer? && LiveMatch::COMPUTER_NAMES[username]) || username.presence || display_name
  end

  # Messages from people still unread by this player: the navbar's Chat badge
  # (NavbarLinks) and the My games link. A computer player's table talk is
  # left out, as it is from the Chat hub. One count through
  # index_messages_on_receiver_id_and_read.
  def unread_messages_count
    Message.with_text.unread_by(self).from_humans.count
  end

  # ---- Who may message whom (task cyvasse-live-chat) ------------------------
  #
  # The one rule, enforced on the server by every way a message is sent (the
  # match chat, a Chat hub reply, a new conversation, the bot API):
  #
  # - never yourself, and never nobody;
  # - between two people, only once they have shared a match: any match, in
  #   any status (a challenge still pending counts, and so does a legacy
  #   imported one);
  # - a computer player only inside a match the two of them are playing,
  #   where its runner reads the chat (the bot API); never from the Chat hub.
  #
  # A conversation that predates the rule (legacy messages between people who
  # never played) stays readable; this only decides whether a new message may
  # be sent in it.
  def can_message?(other, match: nil)
    return false if other.nil? || other.id == id
    return match.present? && match.player?(self) && match.player?(other) if computer? || other.computer?

    shared_match_with?(other)
  end

  def shared_match_with?(other)
    Match.where(home_user_id: id, away_user_id: other.id)
         .or(Match.where(home_user_id: other.id, away_user_id: id)).exists?
  end

  # The people this player has shared a match with, newest match first (never
  # a computer player): who they may start a conversation with.
  def played_humans
    other = Arel.sql(self.class.sanitize_sql_array([ "CASE WHEN home_user_id = ? THEN away_user_id ELSE home_user_id END", id ]))
    latest = Match.involving(self).group(other).order(Arel.sql("MAX(matches.id) DESC")).pluck(other)
    people = User.humans.where(id: latest - [ id ]).index_by(&:id)
    latest.filter_map { |user_id| people[user_id] }
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

  # Tries per save before giving up on the slug index: the first few take the
  # next numeric suffix, the rest a random token no race can share.
  SLUG_SUFFIX_TRIES = 2
  SLUG_SAVE_TRIES = 5
  SLUG_INDEX = "index_users_on_slug".freeze

  # A save that loses the slug to a concurrent one retries with a fresh slug.
  # The savepoint keeps a caller's outer transaction usable after the failed
  # statement; any other unique violation is re-raised untouched.
  def create_or_update(**options, &block)
    @slug_conflicts = 0
    begin
      self.class.transaction(requires_new: true) { super(**options, &block) }
    rescue ActiveRecord::RecordNotUnique => e
      raise unless slug_index_violation?(e) && (@slug_conflicts += 1) < SLUG_SAVE_TRIES

      retry
    end
  ensure
    @slug_conflicts = 0
  end

  # Matched on the constraint Postgres names in the error, not the message text:
  # an email or username violation whose DETAIL quotes a value containing the
  # index name must still raise.
  def slug_index_violation?(error)
    result = error.cause.respond_to?(:result) ? error.cause.result : nil
    result&.error_field(PG::Result::PG_DIAG_CONSTRAINT_NAME) == SLUG_INDEX
  end

  def slug_stem
    [ name, username ].each do |source|
      stem = source.to_s.parameterize
      return stem if stem.present?
    end
    nil
  end

  # The held slug fits when the name is unchanged, or when it changed to one
  # with the same stem ("Carl" to "CARL" keeps carl-2).
  def slug_stands?(stem)
    return true unless will_save_change_to_name?

    stem.present? && slug.match?(/\A#{Regexp.escape(stem)}(-\d+)?\z/)
  end

  def slug_taken?(candidate)
    User.where(slug: candidate).where.not(id: id).exists?
  end

  # parameterize leaves only [a-z0-9_-], so the stem is safe inside the pattern.
  def highest_slug_suffix(stem)
    User.where.not(id: id).where("slug ~ ?", "^#{stem}-[0-9]{1,9}$")
        .maximum(Arel.sql("substring(slug from '[0-9]+$')::integer")).to_i.clamp(1..)
  end

  def random_slug
    "user-#{SecureRandom.alphanumeric(10).downcase}"
  end

  def username_free_in_any_case
    return if username.blank?

    taken = User.where("lower(username) = ?", username.downcase).where.not(id: id).exists?
    errors.add(:username, "is taken") if taken
  end
end
