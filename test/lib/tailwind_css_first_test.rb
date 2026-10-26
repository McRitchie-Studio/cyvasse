require "test_helper"

# [unit] Tailwind is CSS-first (studio-engine >= 0.114.2, its README
# "Tailwind"; task satellites-adopt-css-first-tailwind). The engine import in
# app/assets/tailwind/application.css brings the design tokens, the class-based
# dark: variant, the scan of every engine directory and the motion layer, so the
# JS preset, its @config line, the safelist and the motion import all went.
# Bringing one back pins this app to the deprecated
# tailwind/studio.tailwind.config.js shim, which the engine deletes once every
# host has adopted: the build would then break.
class TailwindCssFirstTest < ActiveSupport::TestCase
  ROOT = Rails.root
  ENTRY = ROOT.join("app/assets/tailwind/application.css")
  STYLESHEETS = Dir[ROOT.join("app/assets/tailwind/**/*.css")].freeze

  test "no stylesheet points Tailwind at a JS config" do
    STYLESHEETS.each do |path|
      refute_match(/^\s*@config\b/, File.read(path), "#{path} must not carry @config: Tailwind is CSS-first")
    end
  end

  test "the JS config and the engine preset stay gone" do
    %w[config/tailwind.config.js tailwind.config.js].each do |path|
      refute ROOT.join(path).exist?, "#{path} came back; move what it carries into application.css instead"
    end
    readers = Dir[ROOT.join("{app,config,lib}/**/*.{js,mjs,cjs,rb,css}")].select do |path|
      File.read(path).include?("studio.tailwind.config")
    end
    assert_empty readers, "nothing may read the engine's deprecated JS preset"
  end

  test "the motion layer comes only through the engine entry" do
    refute ROOT.join("lib/tasks/tailwindcss_engine_motion.rake").exist?
    STYLESHEETS.each do |path|
      refute_includes File.read(path), "studio_engine_motion", "#{path}: host.css already imports engine-motion.css"
    end
  end

  test "the entry imports Tailwind, then the engine" do
    imports = File.read(ENTRY).scan(/^@import\s+["']([^"']+)["']/).flatten
    assert_equal [ "tailwindcss", "../builds/tailwind/studio_engine" ], imports.first(2)
  end

  test "vendor/bundle is excluded only for Markdown" do
    excluded = File.read(ENTRY).scan(/^@source\s+not\s+["']([^"']+)["']/).flatten
    assert_includes excluded, "../../../vendor/bundle/**/*.md"
    refute excluded.any? { |glob| glob.match?(%r{vendor/bundle/?(\*\*)?/?\z}) },
           "excluding all of vendor/bundle drops every engine class from the CI and Heroku builds"
  end
end
