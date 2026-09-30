# The public pages a search engine should index, and what each one tells it
# (task cyvasse-seo-profile). One source for the <title>, the meta
# description, the canonical path, the Open Graph card and /sitemap.xml, so a
# page cannot appear in the sitemap under one name and in its own head under
# another.
#
# A view opts in with `seo_page :rules` (SeoHelper). Every page that does NOT
# is served with <meta name="robots" content="noindex">: sign-in, onboarding,
# a match, /live/:id, the inbox and the admin pages stay out of the index by
# default, and a new public page has to be named here to be found.
#
# Titles stay under 60 characters and descriptions under 160, the lengths a
# results page shows before it truncates (test/models/seo_page_test.rb).
class SeoPage
  Page = Data.define(:key, :path, :title, :description, :heading, :changefreq, :priority)

  SITE_NAME = "Cyvasse".freeze

  # When the copy on the static pages last changed: their sitemap <lastmod>.
  # Bump it with a copy change worth a recrawl.
  CONTENT_UPDATED = Date.new(2026, 9, 30)

  PAGES = [
    Page.new(
      key: :home, path: "/", heading: "Home", changefreq: "daily", priority: "1.0",
      title: "Cyvasse: Play the Game of Thrones Board Game Online",
      description: "Play Cyvasse, the hex-board strategy game from A Song of Ice and Fire, free in " \
                   "your browser: live matchmaking, a computer opponent, no download."
    ),
    Page.new(
      key: :play, path: "/play", heading: "Play", changefreq: "monthly", priority: "0.9",
      title: "Play Cyvasse Online Free Against the Computer",
      description: "Set up your army in secret and play a full game of Cyvasse against a computer " \
                   "opponent. Free, no account and no download: it runs in your browser."
    ),
    Page.new(
      key: :rules, path: "/rules", heading: "Rules", changefreq: "monthly", priority: "0.8",
      title: "Cyvasse Rules: How to Play, Pieces and Combat",
      description: "The complete Cyvasse rules: the goal, the secret army setup, who moves first, " \
                   "how every piece moves and fights, and the special rules."
    ),
    Page.new(
      key: :pieces, path: "/pieces", heading: "Pieces", changefreq: "monthly", priority: "0.6",
      title: "Cyvasse Pieces: Every Unit in Both Art Styles",
      description: "Meet the Cyvasse army, from the King and the Dragon to the Rabble and the " \
                   "Mountain, in the original pencil drawings and the coloured vector art."
    ),
    Page.new(
      key: :about, path: "/about", heading: "About", changefreq: "yearly", priority: "0.5",
      title: "About Cyvasse, the Game from A Song of Ice and Fire",
      description: "How Cyvasse, the game George R. R. Martin describes in A Song of Ice and Fire, " \
                   "was given a full set of rules and rebuilt as a free online game."
    ),
    Page.new(
      key: :leaderboard, path: "/leaderboard", heading: "Leaderboard", changefreq: "hourly", priority: "0.7",
      title: "Cyvasse Leaderboard: the Top Players Online",
      description: "The best Cyvasse players online: a point for every live game finished, three " \
                   "for a win, and the all-time record from the original site."
    ),
    # /leaderboard?board=all-time is its own page, with its own canonical, but
    # the sitemap lists only the live board: the tab links to it.
    Page.new(
      key: :all_time_leaderboard, path: "/leaderboard?board=all-time", heading: "All-time leaderboard",
      changefreq: "daily", priority: nil,
      title: "All-Time Cyvasse Leaderboard: Every Player's Record",
      description: "Every Cyvasse player's won and lost record, ranked by wins, including the games " \
                   "played on the original Cyvasse site since 2014."
    )
  ].freeze

  BY_KEY = PAGES.index_by(&:key).freeze

  def self.find(key) = BY_KEY.fetch(key.to_sym)

  # The pages /sitemap.xml lists: every page with a priority.
  def self.sitemap_pages = PAGES.select(&:priority)

  # The date a crawler should believe the page last changed. The leaderboard
  # and the home page (which carries its top ten) move with every finished
  # game; the rest with their copy.
  def self.lastmod(page)
    return CONTENT_UPDATED unless %i[home leaderboard].include?(page.key)

    [ Match.finished.maximum(:finished_at)&.to_date, CONTENT_UPDATED ].compact.max
  end

  # The home page's questions and answers: shown on the page and, word for
  # word, in its FAQPage JSON-LD (Google reads only an FAQ the page shows).
  def self.faq
    [
      [ "What is Cyvasse?",
        "Cyvasse is the strategy board game played in George R. R. Martin's A Song of Ice and Fire, " \
        "the books behind Game of Thrones. The books never give its full rules, so this version " \
        "fills them in: two players, a hexagonal board of #{CyvasseRules::Board::HEX_COUNT} hexes, " \
        "and armies of #{Rulebook.army_size} pieces set up in secret." ],
      [ "Can I play Cyvasse online for free?",
        "Yes. Cyvasse is free to play in your browser, with nothing to download. Press Play Now " \
        "for a live game against another player (a computer steps in if nobody turns up), or play " \
        "the computer at any time." ],
      [ "Do I need an account to play?",
        "No. You can play the computer or a live game as a guest. Sign in with an email link or " \
        "Google to challenge friends by username, keep your games and appear on the leaderboard." ],
      [ "How do you win at Cyvasse?",
        "Capture your opponent's King. Each player hides their King somewhere in their opening " \
        "array, so half the game is guessing where it is and the other half is keeping yours safe." ],
      [ "Is this the Cyvasse from Game of Thrones?",
        "It is the game from the books. Cyvasse appears in A Feast for Crows and A Dance with Dragons, " \
        "where Tyrion Lannister plays it on his way to Meereen. The show left it out, so these rules " \
        "are built from what the books describe." ],
      [ "Can I play a friend?",
        "Yes. Sign in, choose a username and challenge a friend by theirs. Online matches are played " \
        "a turn at a time, and Cyvasse emails you when it is your move." ]
    ]
  end
end
