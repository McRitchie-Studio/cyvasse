# frozen_string_literal: true

# The crumb trail over a page header's title (studio-engine's studio/_page_header,
# rendered with crumbs: studio_crumbs(...)) walks Studio.crumbs, the engine's one
# parent map. Each page with children is named here once; a page names only its
# parent. Task cyvasse-standard-page-headers.
#
# The public title-row pages (My games, Chat, the Leaderboard, the Pieces, the
# legal pages) sit under Home. A conversation sits under Chat, the username page
# under My games, and the leaderboard's sign-in under the Leaderboard. The admin
# pages have no admin index, so Conversations, the page every admin link leads
# back to, is the admin trail's root: the Message Board, the email sign-ins, a
# conversation and a match sit under it. The marketing heroes (home, Rules,
# About, Cyvasse Night) and the game surfaces carry their own headers, not the
# page header, so they need no entry. to_prepare, so a development reload
# redraws the map instead of keeping a stale one.
Rails.application.config.to_prepare do
  Studio.crumbs.clear.draw do
    page :home, "Home", :root_path
    page :my_games, "My games", :matches_path, parent: :home
    page :chat, "Chat", :conversations_path, parent: :home
    page :leaderboard, "Leaderboard", :leaderboard_path, parent: :home
    page :admin_conversations, "Conversations", :admin_conversations_path
  end
end
