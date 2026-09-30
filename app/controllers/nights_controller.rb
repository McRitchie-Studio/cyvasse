# Cyvasse Night (task cyvasse-night-event-page; the event is CyvasseNight).
# Public, like the landing page the invitations point past.
#
#   GET /night       the event page: before, during or after the night
#   GET /night.ics   the night as a calendar file, for "Add to calendar"
class NightsController < ApplicationController
  skip_before_action :require_authentication

  def show
    @night = CyvasseNight.current
    @phase = @night.phase
    respond_to do |format|
      format.html do
        @presence = CyvasseNight.presence if @phase == :during
        @tonight = @night.leaderboard unless @phase == :before
      end
      format.ics do
        send_data @night.to_ics(helpers.seo_absolute_url(night_path)),
                  type: :ics, disposition: "attachment", filename: @night.ics_filename
      end
    end
  end
end
