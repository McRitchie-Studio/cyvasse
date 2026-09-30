# What the chat pushes over the websocket (task cyvasse-live-chat), as Turbo
# Stream actions on the streams ChatStreams names:
#
#   a new message    the pair stream: append it to the thread (the hub thread
#                    and the match chat carry the same list id); each
#                    person's own stream: their hub row moves to the top,
#                    and the receiver's navbar badge counts it
#   messages read    the reader's own stream: their badge and hub row
#
# Rendered outside any request, so every partial takes its viewer as a local
# and builds paths, never URLs. A computer player has no browser: nothing is
# sent to its stream, its conversations have no hub row, and its messages
# never count toward a badge.
#
# Each one, rendering included, runs inside Studio::Cable.safe_broadcast, so
# neither a Redis hiccup nor a template error fails the message that was
# saved.
module ChatBroadcasts
  # The navbar's Chat link, in the desktop bar and the phone row alike
  # (NavbarLinks::CHAT). The engine's link has no id, so the badge is
  # replaced by updating the link's contents.
  NAV_LINK = %(header nav a[href="#{NavbarLinks::CHAT}"]).freeze

  module_function

  def message_created(message)
    guarded { message_created!(message) }
  end

  def read(reader, other = nil)
    guarded { read!(reader, other) }
  end

  # ---- the stream actions -----------------------------------------------------

  def message_created!(message)
    sender, receiver = message.sender, message.receiver
    broadcast(ChatStreams.pair(sender, receiver), [
      action(:remove, target: "#{ChatStreams.thread_id(sender, receiver)}_empty"),
      action(:append, target: ChatStreams.thread_id(sender, receiver),
                      html: render("messages/message", message:, viewer: nil, show_match: true,
                                                       match_link: ->(match) { "/matches/#{match.id}" }))
    ])
    return if sender.computer? || receiver.computer?

    [ sender, receiver ].each do |viewer|
      other = viewer == sender ? receiver : sender
      streams = hub_row_moved(viewer, other)
      streams << badge(viewer) if viewer == receiver
      broadcast(ChatStreams.user(viewer), streams)
    end
  end

  def read!(reader, other)
    streams = [ badge(reader) ]
    if other && !other.computer? && (conversation = Conversation.for_pair(reader, other))
      streams << action(:replace, target: row_id(other), html: row(conversation, reader))
    end
    broadcast(ChatStreams.user(reader), streams)
  end

  def hub_row_moved(viewer, other)
    conversation = Conversation.for_pair(viewer, other)
    return [] unless conversation

    [ action(:remove, target: "say_hi_#{other.id}"),
      action(:remove, target: "chat_hub_empty"),
      action(:remove, target: row_id(other)),
      action(:prepend, target: "chat_conversations", html: row(conversation, viewer)) ]
  end

  def badge(viewer)
    action(:update, targets: NAV_LINK, html: render("chat/nav_label", count: viewer.unread_messages_count))
  end

  def row_id(other) = "conversation_#{other.id}"

  def row(conversation, viewer)
    render("conversations/row", conversation:, viewer:)
  end

  def action(name, html: nil, **target)
    helpers.turbo_stream_action_tag(name, **target, template: html)
  end

  def render(partial, **locals)
    ApplicationController.render(partial:, locals:, formats: [ :html ])
  end

  def helpers = ApplicationController.helpers

  def broadcast(stream, actions)
    return if actions.empty?

    Turbo::StreamsChannel.broadcast_stream_to(stream, content: helpers.safe_join(actions))
  end

  # Rendering and sending both: a failure lands in ErrorLog, never in the
  # request that saved the message or marked it read.
  def guarded(&block) = Studio::Cable.safe_broadcast(&block)
end
