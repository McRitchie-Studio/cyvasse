# What a signed-in player still has to fill in, and the one place that says so
# (task cyvasse-legacy-onboarding-handoff). OnboardingController walks the
# steps; ApplicationController sends a player there after a sign-in when the
# account is incomplete.
#
#   welcome   a legacy player sees what came across from the old game
#   username  the public name: blank, or failing today's rules (and, for a
#             legacy player, confirmed once); never settled by a skip
#   profile   display name, piece skin, and an optional birth date
#   contact   how to sign in next time, and "Keep me posted about Cyvasse"
#
# A step is missing until its data is there or the player finished or skipped
# it (users.onboarding_steps). "Skip for now" records nothing, so the next
# sign-in resumes where the player left.
module User::Onboarding
  extend ActiveSupport::Concern

  STEPS = %w[welcome username profile contact].freeze
  STATUSES = %w[shown done skipped].freeze
  SETTLED = %w[done skipped].freeze

  class_methods do
    # Where the flow loses people, for the admin: per step, how many players
    # reached it and how many are still sitting on it (shown), finished it
    # (done) or passed it over (skipped). One query.
    #   { "welcome" => { "shown" => 3, "done" => 40, "skipped" => 0, "reached" => 43 }, ... }
    def onboarding_funnel
      counts = connection.select_rows(<<~SQL)
        SELECT step.key, step.value->>'status', COUNT(*)
        FROM users CROSS JOIN LATERAL jsonb_each(users.onboarding_steps) AS step
        GROUP BY 1, 2
      SQL
      STEPS.index_with do |step|
        row = STATUSES.index_with { |status| counts.find { |k, st, _| k == step && st == status }&.last.to_i }
        row.merge("reached" => row.values.sum)
      end
    end
  end

  # The steps still to do, in order.
  def onboarding_missing
    STEPS.select { |step| onboarding_step_missing?(step) }
  end

  # Incomplete: the flow opens itself after a sign-in. Only an account with a
  # real gap counts: a legacy player not yet welcomed, no usable username, or
  # no name. A missing skin or email preference alone waits for the flow.
  # Guests, computers and admins (operators, who can open /onboarding
  # themselves) are never sent.
  def onboarding_due?
    return false if guest? || computer? || admin?

    missing = onboarding_missing
    missing.include?("welcome") || missing.include?("username") || (missing.include?("profile") && name.blank?)
  end

  # The steps this player's flow has, missing or not (for "Step 2 of 4").
  def onboarding_flow
    legacy_id.present? ? STEPS : STEPS - %w[welcome]
  end

  def onboarding_status(step)
    onboarding_steps.dig(step, "status")
  end

  # Records a step as shown, done or skipped. A settled step is never set back
  # to shown by a later visit.
  def record_onboarding!(step, status)
    raise ArgumentError, "unknown step #{step}" unless STEPS.include?(step)
    raise ArgumentError, "unknown status #{status}" unless STATUSES.include?(status)
    return if status == "shown" && SETTLED.include?(onboarding_status(step))

    update_column(:onboarding_steps, onboarding_steps.merge(step => { "status" => status, "at" => Time.current.iso8601 }))
  end

  def username_playable?
    username.present? && username.match?(User::USERNAME_FORMAT)
  end

  # A free name built from the legacy one (or the email) that passes today's
  # rules: stray characters become underscores, then a number is added until
  # nobody holds it in any case, and it is not reserved (User.username_reserved?).
  # One query for every candidate.
  def suggested_username
    base = (username.presence || email.to_s.split("@").first.to_s).strip
      .gsub(/[^A-Za-z0-9_]+/, "_").gsub(/_+/, "_").delete_prefix("_").delete_suffix("_").first(16)
    base = "player" if base.length < 3 || base.match?(User::GUEST_USERNAME)
    candidates = [ base, *(2..99).map { |n| "#{base}_#{n}" } ].reject { |candidate| User.username_reserved?(candidate) }
    taken = User.where("lower(username) IN (?)", candidates.map(&:downcase)).where.not(id:).pluck(Arel.sql("lower(username)"))
    candidates.find { |candidate| !taken.include?(candidate.downcase) } || "#{base.first(11)}_#{SecureRandom.hex(4)}"
  end

  # What came across from the old game, counted from the imported matches and
  # lineups: two queries whatever the history's size (an expired match was
  # never started, so it is not a game played).
  def legacy_stats
    played, wins, first = Match.involving(self).where.not(legacy_id: nil)
      .where("matches.finish_reason IS DISTINCT FROM 'expired'")
      .pick(Arel.sql("COUNT(*)"), Arel.sql(Match.sanitize_sql_array([ "COUNT(*) FILTER (WHERE winner_id = ?)", id ])), Arel.sql("MIN(created_at)"))
    { played: played.to_i, wins: wins.to_i, first_game_on: first&.to_date, lineups: setups.count }
  end

  private

  # A username online play cannot use stays missing even if skipped: Play Now
  # asks for it (RequiresUsername), and so does the next sign-in.
  def onboarding_step_missing?(step)
    return true if step == "username" && !username_playable?
    return false if SETTLED.include?(onboarding_status(step))

    case step
    when "welcome", "username" then legacy_id.present?
    when "profile" then name.blank? || piece_skin.blank?
    when "contact" then email_updates.nil?
    end
  end
end
