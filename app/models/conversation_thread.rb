# One conversation's messages grouped by the game they were sent in (epic
# cyvasse-revival piece 12b; Alex: "group my game and show the full messages
# with right and left bubbles"). The admin thread page draws it.
#
# A group is one match's messages, or the messages sent outside any match.
# Groups run newest first (by their latest message) and messages oldest first
# inside each. It stays cheap on the legacy history (46,976 messages): every
# query reads the pair through index_messages_on_conversation, a page holds
# GROUPS_PER_PAGE groups, and a group shows at most its latest PER_GROUP
# messages; `game` pages through one group whole.
#
#   thread = ConversationThread.new(low_user, high_user)
#   thread.total                 every message between them
#   thread.page(2)               a Page of groups, each with its messages
#   thread.game("12", page: 1)   one group, PER_PAGE messages a page, or nil
class ConversationThread
  GROUPS_PER_PAGE = 10
  PER_GROUP = 200
  PER_PAGE = 200
  NONE = "none".freeze

  # One game's messages, or those outside any game (match nil). `count` is
  # every message in the group; `messages` the ones loaded, oldest first.
  Group = Struct.new(:match, :messages, :count, :first_at, :last_at, :first_number, keyword_init: true) do
    def key = match ? match.id.to_s : NONE
    def earlier_count = messages.empty? ? 0 : first_number - 1
    def complete? = messages.size == count
  end

  # A page of groups, or of one group's messages. `total` counts what is paged.
  Page = Struct.new(:groups, :page, :total, :per_page, keyword_init: true) do
    def pages = [ (total.to_f / per_page).ceil, 1 ].max
    def next_page = page < pages ? page + 1 : nil
    def prev_page = page > 1 ? page - 1 : nil
  end

  attr_reader :low_user, :high_user

  def initialize(low_user, high_user)
    @low_user = low_user
    @high_user = high_user
  end

  def messages = Message.in_pair(low_user.id, high_user.id)

  def total = summaries.sum { _1[:count] }

  # Page `number` of the groups, newest first, each with its latest PER_GROUP
  # messages oldest first.
  def page(number)
    number = [ number.to_i, 1 ].max
    shown = summaries.drop((number - 1) * GROUPS_PER_PAGE).first(GROUPS_PER_PAGE)
    Page.new(groups: build_groups(shown), page: number, total: summaries.size, per_page: GROUPS_PER_PAGE)
  end

  # One group whole, a page of PER_PAGE messages at a time, oldest first;
  # nil when `key` ("12", or "none") is not a group of this conversation.
  def game(key, page: 1)
    summary = summaries.find { _1[:key] == key.to_s }
    return unless summary

    number = [ page.to_i, 1 ].max
    offset = (number - 1) * PER_PAGE
    rows = in_group(summary[:match_id]).chronological.includes(:sender).offset(offset).limit(PER_PAGE).to_a
    group = Group.new(match: matches_for([ summary ])[summary[:match_id]], messages: rows, count: summary[:count],
                      first_at: summary[:first_at], last_at: summary[:last_at], first_number: offset + 1)
    Page.new(groups: [ group ], page: number, total: summary[:count], per_page: PER_PAGE)
  end

  private

  # Every group's size and span, newest first: one grouped query.
  def summaries
    @summaries ||= messages.reorder(nil).group(:match_id)
                           .pluck(:match_id, Arel.sql("COUNT(*)"), Arel.sql("MIN(messages.created_at)"),
                                  Arel.sql("MAX(messages.created_at)"), Arel.sql("MAX(messages.id)"))
                           .map { |match_id, count, first_at, last_at, last_id| { match_id:, key: match_id ? match_id.to_s : NONE, count:, first_at:, last_at:, last_id: } }
                           .sort_by { [ _1[:last_at], _1[:last_id] ] }.reverse
  end

  # The shown groups' latest PER_GROUP messages each, in one windowed query.
  def build_groups(shown)
    return [] if shown.empty?

    ranked = messages.where(match_id: shown.map { _1[:match_id] })
                     .select("messages.*, ROW_NUMBER() OVER (PARTITION BY messages.match_id ORDER BY messages.created_at DESC, messages.id DESC) AS nth")
    rows = Message.from(ranked, :messages).where("messages.nth <= ?", PER_GROUP)
                  .order(:created_at, :id).includes(:sender).to_a.group_by(&:match_id)
    matches = matches_for(shown)
    shown.map do |summary|
      loaded = rows.fetch(summary[:match_id], [])
      Group.new(match: matches[summary[:match_id]], messages: loaded, count: summary[:count],
                first_at: summary[:first_at], last_at: summary[:last_at],
                first_number: summary[:count] - loaded.size + 1)
    end
  end

  def in_group(match_id) = messages.where(match_id: match_id)

  def matches_for(shown)
    ids = shown.filter_map { _1[:match_id] }
    ids.empty? ? {} : Match.where(id: ids).includes(:winner).index_by(&:id)
  end
end
