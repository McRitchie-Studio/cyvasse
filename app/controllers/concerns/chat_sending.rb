# Sending a chat message (task cyvasse-live-chat), shared by the match chat
# and the Chat hub: the rate limit, and the Turbo Stream answer to the
# composer.
#
# The answer appends the sender's own message to their thread at once, drawn
# as theirs; the same message also arrives over the pair stream moments
# later, and Turbo keeps one copy (both carry id message-<id>). A refused
# message puts the reason in the thread's error line and leaves the draft
# for the sender to fix.
module ChatSending
  extend ActiveSupport::Concern

  # Per player, per controller. The test environment's cache is the null
  # store, which never counts, so tests get a store of their own.
  RATE = 20
  RATE_WINDOW = 1.minute
  RATE_STORE = Rails.env.test? ? ActiveSupport::Cache::MemoryStore.new : Rails.cache
  TOO_FAST = "You are sending messages too fast. Wait a moment and try again.".freeze

  class_methods do
    def rate_limit_sending(only:)
      rate_limit to: RATE, within: RATE_WINDOW, store: RATE_STORE, only:,
                 by: -> { current_user.id }, with: -> { refuse_message(TOO_FAST, :too_many_requests) }
    end
  end

  private

  # Sends with the block (which creates the message) and answers the composer.
  def send_message(thread_id)
    message = nil
    error = nil
    rescue_and_log(target: current_user) do
      message = yield
    rescue ActiveRecord::RecordInvalid => e
      error = e.record.errors.full_messages.to_sentence
    end
    return refuse_message(error, :unprocessable_entity, thread_id) if error

    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: [
          turbo_stream.remove("#{thread_id}_empty"),
          turbo_stream.append(thread_id, partial: "messages/message",
                                         locals: { message:, viewer: current_user, show_match: true, match_link: ->(m) { match_path(m) } }),
          turbo_stream.replace("#{thread_id}_error", partial: "chat/error", locals: { thread_id:, error: nil })
        ]
      end
      format.html { redirect_to after_send_path, status: :see_other }
    end
  end

  def refuse_message(error, status, thread_id = chat_thread_id)
    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: turbo_stream.replace("#{thread_id}_error", partial: "chat/error", locals: { thread_id:, error: }),
               status:
      end
      format.html { redirect_to after_send_path, alert: error, status: :see_other }
      format.any { head status }
    end
  end
end
