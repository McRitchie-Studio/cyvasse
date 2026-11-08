require "test_helper"

# [unit] Task cyvasse-standard-page-headers: the app's one crumb parent map
# (config/initializers/studio_crumbs.rb) resolves each page's trail, root first,
# through studio_crumbs, the helper every page header calls.
class StudioCrumbsTest < ActionView::TestCase
  include Studio::CrumbsHelper

  def labels(trail) = trail.map { |crumb| crumb[:label] }

  test "[unit] the public pages walk up to Home" do
    assert_equal [ { label: "Home", href: "/" } ], studio_crumbs(parent: :home)
    assert_equal [ { label: "Home", href: "/" } ], studio_crumbs(:my_games)
    assert_equal [ { label: "Home", href: "/" } ], studio_crumbs(:chat)
  end

  test "[unit] a conversation sits under Chat, under Home" do
    assert_equal [ { label: "Home", href: "/" }, { label: "Chat", href: conversations_path } ], studio_crumbs(parent: :chat)
  end

  test "[unit] Conversations is the admin root, and its children carry it alone" do
    assert_empty studio_crumbs(:admin_conversations)
    assert_equal [ "Conversations" ], labels(studio_crumbs(parent: :admin_conversations))
    assert_equal admin_conversations_path, studio_crumbs(parent: :admin_conversations).first[:href]
  end

  test "[unit] a key the map lacks raises in test, so a typo fails here" do
    assert_raises(Studio::Crumbs::UnknownPage) { studio_crumbs(:admin) }
  end
end
