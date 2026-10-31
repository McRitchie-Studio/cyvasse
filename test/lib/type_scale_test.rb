# frozen_string_literal: true

require "test_helper"

# [unit] Task cyvasse-adopts-type-scale: every Tailwind font size this app uses
# lands on one of the engine's five roles (app/assets/tailwind/type_scale.css),
# at the multiples Studio::TypeScale::ROLES names; no source or stylesheet sets
# a size of its own; and the four Studio.type_* settings are the ones the
# initializer spells (Cyvasse has no hub brand kit, so the engine defaults).
class TypeScaleTest < ActiveSupport::TestCase
  CSS = Rails.root.join("app/assets/tailwind/type_scale.css")
  # Alex McRitchie's go of 2026-10-29 (the hub's map): the old sizes sorted onto the five steps.
  EXPECTED = {
    "3xs" => 0.75, "2xs" => 0.75, "xs" => 0.75,
    "sm" => 1, "base" => 1,
    "lg" => 1.5, "xl" => 1.5, "2xl" => 1.5,
    "3xl" => 3, "4xl" => 3,
    "5xl" => 6, "6xl" => 6, "7xl" => 6, "8xl" => 6, "9xl" => 6
  }.freeze
  SIZE_CLASS = /(?<![\w-])text-(3xs|2xs|xs|sm|base|lg|[2-9]?xl)(?![\w-])/
  KIT = { type_base: 16, type_dense_base: 14, type_display_weight: 800, type_text_weight: 300 }.freeze
  ROLE_SIZE = /\Acalc\(var\(--type-base, 16px\) \* [\d.]+\)\z/
  FIXED_SIZE = /text-\[[\d.]+(px|rem|em)\]|font-size:\s*[\d.]+(px|rem|em)/

  # The only sources allowed a size off the scale, each for a measured reason:
  EXEMPT = {
    # Email clients read neither CSS variables nor the theme tag, so an email
    # keeps its inline pixel sizes.
    "app/views/layouts/mailer.html.erb" => "email",
    "app/views/user_mailer/magic_link.html.erb" => "email",
    # The navbar's rank badge mirrors the engine's own
    # StudioNavbarHelper::NAVBAR_BADGE_CLASS (text-[10px]), and
    # test/views/navbar_links_test.rb holds the two equal; it moves when the
    # engine's does.
    "app/javascript/cyvasse/game_over.js" => "engine badge mirror"
  }.freeze

  def mapped
    CSS.read.scan(/--text-([0-9a-z]+): calc\(var\(--type-base, 16px\) \* ([\d.]+)\);/).to_h { |size, n| [ size, n.to_f ] }
  end

  def sources = Dir[Rails.root.join("app/{views,components,controllers,helpers,javascript,models,services}/**/*.{erb,rb,js}")]

  def relative(path) = Pathname(path).relative_path_from(Rails.root).to_s

  test "every Tailwind size maps to its step, inline so type-dense reaches it" do
    assert_equal EXPECTED.transform_values(&:to_f), mapped
    assert_match(/@theme inline \{/, CSS.read, "a plain @theme resolves on :root, and type-dense pages would keep 16px")
  end

  test "every multiple is one of the engine's roles, and each role is reached" do
    roles = Studio::TypeScale::ROLES.map { |_, multiple, _| multiple.to_f }
    assert_empty mapped.values.uniq - roles
    assert_equal roles.sort, mapped.values.uniq.sort
  end

  test "every size class in the app is a mapped one" do
    used = sources.flat_map { |path| File.read(path).scan(SIZE_CLASS).flatten }.uniq
    refute_empty used, "the scan found no size classes, so it proved nothing"
    assert_empty used - mapped.keys
  end

  test "no source sets an arbitrary font size, outside the named exemptions" do
    offenders = sources.select { |path| File.read(path).match?(FIXED_SIZE) }.map { |path| relative(path) }
    assert_empty offenders - EXEMPT.keys
    # Each exemption still needs one: a stale entry would excuse a future size.
    EXEMPT.each_key { |path| assert_match FIXED_SIZE, Rails.root.join(path).read, "#{path} no longer needs its exemption" }
  end

  test "the stylesheets set every font size on a role" do
    %w[app/assets/tailwind/application.css app/assets/stylesheets/game.css].each do |path|
      sizes = Rails.root.join(path).read.scan(/font-size:\s*([^;]+);/).flatten
      refute_empty sizes, "#{path} sets sizes; finding none means the scan broke"
      assert_empty sizes.grep_v(ROLE_SIZE), path
      assert_empty sizes.map { |size| size[/\* ([\d.]+)\)/, 1].to_f } - Studio::TypeScale::ROLES.map { |_, n, _| n.to_f }, path
    end
  end

  test "a page's inline style sets its sizes on a role too" do
    sizes = Rails.root.join("app/views/live_seeks/show.html.erb").read.scan(/font-size:\s*([^;]+);/).flatten
    refute_empty sizes, "the Play Now splash sets sizes; finding none means the scan broke"
    assert_empty sizes.grep_v(ROLE_SIZE)
  end

  test "the map is imported after the engine layer, so it wins" do
    css = Rails.root.join("app/assets/tailwind/application.css").read
    engine = css.index('@import "../builds/tailwind/studio_engine"')
    map = css.index('@import "./type_scale.css"')
    assert engine && map, "both imports must be present"
    assert_operator engine, :<, map
  end

  test "the Studio.type_* settings are the initializer's" do
    assert_equal KIT, KIT.keys.index_with { |name| Studio.public_send(name) }
  end
end
