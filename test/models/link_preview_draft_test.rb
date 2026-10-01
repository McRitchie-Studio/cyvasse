require "test_helper"

# [unit] The drafted site identity (config/initializers/studio.rb) is the home
# page's SEO copy, word for word, so a shared link to any page without copy of
# its own says what the home page says (task cyvasse-adopts-link-preview). The
# operator edits it at /admin/link_preview; a saved value wins over the draft.
class LinkPreviewDraftTest < ActiveSupport::TestCase
  teardown { Studio::SiteIdentity.bust_cache! }

  test "the draft is the home page's title and description" do
    home = SeoPage.find(:home)
    assert_equal home.title, Studio.site_title
    assert_equal home.description, Studio.site_description
  end

  test "the engine writes the preview tags: no template here holds them off" do
    assert_equal :auto, Studio.link_preview_tags
    assert Studio.link_preview_tags?
  end

  test "an operator's saved words win over the draft, and blanks fall back to it" do
    assert_equal Studio.site_title, Studio.site_identity[:title]

    Studio::SiteIdentity.current!.update!(title: "Cyvasse, Online", description: "")
    identity = Studio.site_identity
    assert_equal "Cyvasse, Online", identity[:title]
    assert_equal Studio.site_description, identity[:description]
  end

  test "the last-resort card is public/og.png, the same picture as the default" do
    assert_equal "/og.png", Studio::SiteIdentity.static_image
    assert_equal Rails.root.join("app/assets/images/og/default.png").binread,
                 Rails.root.join("public/og.png").binread
  end
end
