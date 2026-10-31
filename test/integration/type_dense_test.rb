# frozen_string_literal: true

require "test_helper"

# [integration] Task cyvasse-adopts-type-scale: an admin-only page reads the type
# scale's 14px dense base through `type-dense` on <body> (on <html> the theme
# tag's unlayered :root rule would win). Cyvasse has two kinds of admin page,
# its own (/admin/*, Admin::BaseController) and the engine's (/admin/theme
# here, behind Studio::ErrorHandling#require_admin), and both are dense. A
# visitor's page, a player's page and the board keep the 16px base, and a
# player turned away from an admin page is never marked dense.
class TypeDenseTest < ActionDispatch::IntegrationTest
  include LiveResults

  def body_classes = css_select("body").first["class"].split

  test "the app's own admin page puts type-dense on body, not html" do
    log_in_as(player("warden", role: "admin"))
    get admin_sign_ins_path
    assert_response :success
    assert_includes body_classes, "type-dense"
    refute_includes css_select("html").first["class"].to_s.split, "type-dense"
  end

  test "the engine's admin page in this layout is dense too" do
    log_in_as(player("warden", role: "admin"))
    get admin_theme_path
    assert_response :success
    assert_includes body_classes, "type-dense"
  end

  test "a public page and the board keep the 16px base" do
    [ root_path, rules_path, leaderboard_path, play_path ].each do |path|
      get path
      assert_response :success
      refute_includes body_classes, "type-dense", path
    end
  end

  test "an admin's own player pages keep the 16px base" do
    log_in_as(player("warden", role: "admin"))
    [ matches_path, conversations_path ].each do |path|
      get path
      assert_response :success
      refute_includes body_classes, "type-dense", path
    end
  end

  test "a player turned away from an admin page is not marked dense" do
    log_in_as(player("arya"))
    get admin_sign_ins_path
    # A 404 renders no layout at all (production serves public/404.html).
    assert_response :not_found

    get admin_theme_path
    assert_response :redirect
    follow_redirect!
    refute_includes body_classes, "type-dense"
  end

  test "the theme tag carries the type scale settings" do
    get root_path
    assert_includes response.body, "--type-base: 16px;"
    assert_includes response.body, "--type-dense-base: 14px;"
    assert_includes response.body, "--type-display-weight: 800;"
    assert_includes response.body, "--type-text-weight: 300;"
  end
end
