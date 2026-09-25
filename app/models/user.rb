class User < ApplicationRecord
  include Sluggable

  # The engine's signed-in user nav renders components/avatar, which needs the
  # avatar attachment plus avatar_initials and avatar_color (the house pattern
  # shared with mcritchie-studio and mcritchie-industries).
  has_one_attached :avatar

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

  def display_name
    name.presence || email&.split("@")&.first || "User"
  end

  def avatar_initials
    display_name.first.upcase
  end

  def avatar_color
    key = name.presence || email.presence || id.to_s
    AVATAR_COLORS[Digest::MD5.hexdigest(key).hex % AVATAR_COLORS.size]
  end

  def admin?
    role == "admin"
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
end
