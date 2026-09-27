# Credits what a player does to the email that brought them (the hub's email
# analytics, tasks email-event-log-webhooks and cyvasse-email-result-beacons).
#
# The hub's click redirect sends a reader here with `?ref=<delivery token>`.
# This remembers the token for thirty days in a cookie, and reports results
# to the hub as beacons — a 1x1 image at <hub>/e/g/<token>?g=<goal>, keyed by
# the token the way the email's own open pixel is:
#
#   signed_in     queued here, once, the first page a signed-in reader loads
#   played_match  fired by the board (cyvasse_game_controller#emailGoal) when
#                 a game starts, from the URL in the email-goal-url meta tag
#
# The hub counts each goal once per email, so a repeated beacon is harmless.
module EmailReferral
  extend ActiveSupport::Concern

  REF_COOKIE = :email_ref
  SIGNED_IN_COOKIE = :email_ref_signed_in
  TOKEN = /\A[\w-]{16,64}\z/
  HUB_URL = ENV.fetch("EMAIL_ANALYTICS_URL", "https://mcritchie.studio").chomp("/")

  included do
    before_action :remember_email_ref
    before_action :queue_signed_in_beacon
    helper_method :email_ref, :email_goal_url, :email_goal_beacons
  end

  private

  def email_ref
    ref = cookies[REF_COOKIE].to_s
    ref if ref.match?(TOKEN)
  end

  # The beacon URL for `goal`, or for the page's JavaScript to finish with a goal.
  def email_goal_url(goal = nil)
    return unless email_ref

    "#{HUB_URL}/e/g/#{email_ref}?g=#{goal}"
  end

  def email_goal_beacons
    @email_goal_beacons ||= []
  end

  def remember_email_ref
    ref = params[:ref].to_s
    return unless ref.match?(TOKEN)

    # A different email starts its own count of results.
    cookies.delete(SIGNED_IN_COOKIE) if cookies[REF_COOKIE] != ref
    cookies[REF_COOKIE] = { value: ref, expires: 30.days, httponly: true, same_site: :lax }
  end

  def queue_signed_in_beacon
    return unless email_ref && logged_in? && cookies[SIGNED_IN_COOKIE] != email_ref

    email_goal_beacons << email_goal_url("signed_in")
    cookies[SIGNED_IN_COOKIE] = { value: email_ref, expires: 30.days, httponly: true, same_site: :lax }
  end
end
