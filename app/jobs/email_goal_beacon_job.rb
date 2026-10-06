require "net/http"

# Fires one hub goal beacon from the server: a GET of <hub>/e/g/<ref>?g=<goal>,
# the same URL the layout and the board draw as an image for signed_in and
# played_match (EmailReferral). Used for survey_completed, which a POST
# reaches with no page left to draw on. The hub counts each goal once per
# email, so a retried beacon is harmless.
class EmailGoalBeaconJob < ApplicationJob
  queue_as :default

  TIMEOUT = 5 # seconds, each to connect and to read

  retry_on Net::OpenTimeout, Net::ReadTimeout, SocketError, SystemCallError, wait: 30.seconds, attempts: 3

  def perform(ref, goal)
    uri = URI(EmailReferral.goal_url(ref, goal))
    response = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https",
                               open_timeout: TIMEOUT, read_timeout: TIMEOUT) { |http| http.get(uri.request_uri) }
    return if response.is_a?(Net::HTTPSuccess)

    Rails.logger.warn("[email-goal] #{goal} beacon answered #{response.code}")
  end
end
