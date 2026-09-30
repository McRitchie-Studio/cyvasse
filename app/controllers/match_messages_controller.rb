# Sending in a match's chat (epic cyvasse-revival piece 12; task
# cyvasse-live-chat). Its two players write it; anyone else gets a 404, as
# for the match itself.
#
# The match page shows the pair's whole conversation (matches/_chat, a
# ChatThread), not only this match's messages, so it carries on from match
# to match; a message sent here still records the match. New messages arrive
# over the pair's stream (ChatBroadcasts); this answers the composer.
class MatchMessagesController < ApplicationController
  include RequiresUsername
  include ChatSending

  before_action :require_username
  before_action :set_match
  rate_limit_sending only: :create

  def create
    send_message(chat_thread_id) { Message.post_in_match!(@match, current_user, params[:message]) }
  end

  private

  def set_match
    @match = Match.involving(current_user).includes(:home_user, :away_user).find(params[:match_id])
  end

  def chat_thread_id = ChatStreams.thread_id(current_user, @match.opponent_of(current_user))

  def after_send_path = match_path(@match)
end
