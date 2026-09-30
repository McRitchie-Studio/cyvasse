# The chat's Turbo Streams channel (task cyvasse-live-chat). A page subscribes
# with turbo_stream_from(name, channel: ChatStreamsChannel), and the stream
# name is checked twice: Turbo's signature (only the server can sign a name,
# and it signs one only into a page it renders for that player), and then
# ChatStreams.permitted?, so a signed name copied out of someone else's page
# still streams nothing to a player it does not belong to.
class ChatStreamsChannel < Turbo::StreamsChannel
  def subscribed
    name = verified_stream_name_from_params
    if name && ChatStreams.permitted?(name, current_user)
      stream_from name
    else
      reject
    end
  end
end
