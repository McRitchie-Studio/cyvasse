# Every message between two people, in any match or none (epic
# cyvasse-revival piece 12). Not a table: a conversation is the unordered
# pair (LEAST, GREATEST) of a message's sender and receiver, which the
# index_messages_on_conversation index covers.
#
#   Conversation.page(scope, page:)   one page of the conversations in a
#                                     Message scope, newest first, loaded in
#                                     four queries whatever the page size
#   Conversation.for_players(query)   the Message scope of the conversations
#                                     a player (username, name or email) is in
class Conversation
  PER_PAGE = 25

  PAIR_LOW = "LEAST(messages.sender_id, messages.receiver_id)".freeze
  PAIR_HIGH = "GREATEST(messages.sender_id, messages.receiver_id)".freeze

  # One page of results, with what the view needs to draw the pager.
  Page = Struct.new(:conversations, :page, :total, :per_page, keyword_init: true) do
    def pages = [ (total.to_f / per_page).ceil, 1 ].max
    def next_page = page < pages ? page + 1 : nil
    def prev_page = page > 1 ? page - 1 : nil
    def first_number = total.zero? ? 0 : ((page - 1) * per_page) + 1
    def last_number = [ page * per_page, total ].min
  end

  attr_reader :low_user, :high_user, :messages_count, :unread_count, :last_message, :last_at, :matches

  def initialize(low_user:, high_user:, messages_count:, unread_count:, last_message:, last_at:, matches:)
    @low_user = low_user
    @high_user = high_user
    @messages_count = messages_count
    @unread_count = unread_count
    @last_message = last_message
    @last_at = last_at
    @matches = matches
  end

  # The conversations in `scope` (a Message relation), newest first. `reader`
  # counts the messages still unread by them.
  def self.page(scope, page: 1, per_page: PER_PAGE, reader: nil)
    page = [ page.to_i, 1 ].max
    grouped = scope.reorder(nil).group(Arel.sql(PAIR_LOW), Arel.sql(PAIR_HIGH))
    total = Message.from(grouped.select(Arel.sql("1")), :conversations).count
    rows = grouped.select(Arel.sql(summary_columns(reader)))
                  .order(Arel.sql("last_at DESC, last_message_id DESC"))
                  .limit(per_page).offset((page - 1) * per_page)
                  .to_a
    Page.new(conversations: hydrate(rows), page: page, total: total, per_page: per_page)
  end

  # Messages whose sender or receiver matches `query` by username, name or
  # email (case-insensitive, substring); every message when blank.
  def self.for_players(query, scope = Message.all)
    query = query.to_s.strip
    return scope if query.empty?

    pattern = "%#{ActiveRecord::Base.sanitize_sql_like(query.downcase)}%"
    players = User.where("lower(username) LIKE :q OR lower(name) LIKE :q OR lower(email) LIKE :q", q: pattern).select(:id)
    scope.where(sender_id: players).or(scope.where(receiver_id: players))
  end

  # The low and high user ids of a pair, in that order, from "12-34".
  def self.parse_key(key)
    ids = key.to_s.split("-", 2).map { |part| Integer(part, 10, exception: false) }
    ids.size == 2 && ids.all? ? ids.minmax : nil
  end

  def self.summary_columns(reader)
    unread = if reader
      ActiveRecord::Base.sanitize_sql_array([ "COUNT(*) FILTER (WHERE messages.receiver_id = ? AND NOT messages.read)", reader.id ])
    else
      "0"
    end
    <<~SQL.squish
      #{PAIR_LOW} AS low_user_id, #{PAIR_HIGH} AS high_user_id,
      COUNT(*) AS messages_count, #{unread} AS unread_count,
      MAX(messages.created_at) AS last_at,
      (ARRAY_AGG(messages.id ORDER BY messages.created_at DESC, messages.id DESC))[1] AS last_message_id,
      ARRAY_REMOVE(ARRAY_AGG(DISTINCT messages.match_id), NULL) AS match_ids
    SQL
  end
  private_class_method :summary_columns

  def self.hydrate(rows)
    users = User.where(id: rows.flat_map { |row| [ row.low_user_id, row.high_user_id ] }.uniq).index_by(&:id)
    messages = Message.where(id: rows.map(&:last_message_id)).index_by(&:id)
    matches = Match.where(id: rows.flat_map(&:match_ids).uniq).index_by(&:id)

    rows.map do |row|
      new(low_user: users[row.low_user_id], high_user: users[row.high_user_id],
          messages_count: row.messages_count, unread_count: row.unread_count.to_i,
          last_message: messages[row.last_message_id], last_at: row.last_at,
          matches: row.match_ids.filter_map { |id| matches[id] }.sort_by(&:id).reverse)
    end
  end
  private_class_method :hydrate

  def key = "#{low_user.id}-#{high_user.id}"
  def users = [ low_user, high_user ]
  def unread? = unread_count.positive?

  # The other person, from `user`'s side.
  def other(user)
    user.id == low_user.id ? high_user : low_user
  end
end
