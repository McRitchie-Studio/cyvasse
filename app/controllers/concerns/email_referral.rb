# Credits what a player does to the email that brought them (the hub's email
# analytics, tasks email-event-log-webhooks and cyvasse-email-result-beacons).
#
# The hub's click redirect sends a reader here with `?ref=<delivery token>`.
# This remembers the token for thirty days in a cookie, and reports results
# to the hub as beacons — a 1x1 image at <hub>/e/g/<token>?g=<goal>, keyed by
# the token the way the email's own open pixel is:
#
#   signed_in     drawn by the layout on the first full page a signed-in
#                 reader sees, and marked sent only once it was drawn
#   played_match  fired by the board (cyvasse_game_controller#emailGoal) when
#                 a game starts, from the URL in the email-goal-url meta tag
#   survey_completed
#                 fired from the server (EmailGoalBeaconJob) when a survey
#                 response credited to the ref completes (the engine's
#                 Studio.on_survey_completed, config/initializers/studio.rb)
#
# The hub counts each goal once per email, so a repeated beacon is harmless;
# a lost one is not, which is why the ref is saved before the sign-in gate
# redirects anyone and the signed_in mark waits for the page that drew it.
#
# EMAIL_ANALYTICS_URL is the hub; production defaults to mcritchie.studio,
# anywhere else to the local hub, so a desk or a test never reports to prod.
module EmailReferral
  extend ActiveSupport::Concern

  REF_COOKIE = :email_ref
  SIGNED_IN_COOKIE = :email_ref_signed_in
  TOKEN = /\A[\w-]{16,64}\z/

  def self.hub_url
    ENV.fetch("EMAIL_ANALYTICS_URL") { Rails.env.production? ? "https://mcritchie.studio" : "http://localhost:3000" }.chomp("/")
  end

  # The hub's beacon URL for `goal` on the email `ref`; with no goal, the stem
  # the board's JavaScript finishes.
  def self.goal_url(ref, goal = nil)
    "#{hub_url}/e/g/#{ref}?g=#{goal}"
  end

  # The email a survey response is credited to (Studio.survey_ref_resolver):
  # this request's ?ref=, else the one the cookie remembers. Never a value that
  # is not a delivery token, so a hand-typed ?ref=test stamps nothing.
  def self.ref_for(controller)
    ref = controller.params[:ref].to_s
    return ref if ref.match?(TOKEN)

    controller.send(:email_ref)
  end

  # Reports `goal` for the email `ref` from the server, for a result that has no
  # page to draw a beacon on (a survey completes in a POST). Nothing without a
  # ref: an answer from a visitor no email brought is credited to no email.
  def self.report_goal(ref, goal)
    return unless ref.to_s.match?(TOKEN)

    EmailGoalBeaconJob.perform_later(ref.to_s, goal.to_s)
  end

  included do
    # Before the engine's require_authentication, which redirects a signed-out
    # reader to /login and would drop the ref with the request.
    prepend_before_action :remember_email_ref
    after_action :mark_signed_in_beacon_sent
    helper_method :email_ref, :email_goal_url, :email_goal_beacons
  end

  private

  def email_ref
    ref = cookies[REF_COOKIE].to_s
    ref if ref.match?(TOKEN)
  end

  # The beacon URL for `goal`, or the stem the page's JavaScript finishes.
  def email_goal_url(goal = nil)
    return unless email_ref

    EmailReferral.goal_url(email_ref, goal)
  end

  # The beacons the layout draws. Calling this is what marks them drawn.
  def email_goal_beacons
    return [] unless signed_in_beacon_due?

    @signed_in_beacon_drawn = true
    [ email_goal_url("signed_in") ]
  end

  def signed_in_beacon_due?
    email_ref.present? && logged_in? && cookies[SIGNED_IN_COOKIE] != email_ref && full_page_request?
  end

  # A page the reader will actually see: not a Turbo frame, a hover prefetch
  # or a JSON call, whose responses never draw the layout's beacon.
  def full_page_request?
    request.format.html? && !request.xhr? && request.headers["Turbo-Frame"].blank? &&
      !request.headers["X-Sec-Purpose"].to_s.include?("prefetch") &&
      !request.headers["Sec-Purpose"].to_s.include?("prefetch")
  end

  def remember_email_ref
    store_email_ref(params[:ref])
  end

  # Also called with the ref inside an email handoff's assertion
  # (EmailHandoffsController), which carries no ?ref= of its own.
  def store_email_ref(ref)
    ref = ref.to_s
    return unless ref.match?(TOKEN)

    # A different email starts its own count of results.
    cookies.delete(SIGNED_IN_COOKIE) if cookies[REF_COOKIE] != ref
    cookies[REF_COOKIE] = { value: ref, expires: 30.days, httponly: true, same_site: :lax }
  end

  def mark_signed_in_beacon_sent
    return unless @signed_in_beacon_drawn && response.successful?

    cookies[SIGNED_IN_COOKIE] = { value: email_ref, expires: 30.days, httponly: true, same_site: :lax }
  end
end
