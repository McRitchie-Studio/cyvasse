require "test_helper"
require "open3"

# [unit] Cyvasse takes its Node tooling from studio-engine
# (lib/studio/node_tooling): the pins in versions.json and the node:test
# importmap hook. This holds the app to both.
class NodeToolingTest < ActiveSupport::TestCase
  REGISTER = Rails.root.join("test/javascript/support/register.mjs")

  test "studio:node:check finds no drift from the engine's pins" do
    assert_empty Studio::NodeTooling.drift(Rails.root)
  end

  test "node_modules is ignored, so the package link is never committed" do
    _out, _err, status = Open3.capture3("git", "check-ignore", "-q", "node_modules/.studio-engine",
                                        chdir: Rails.root.to_s)

    assert status.success?, ".gitignore must ignore /node_modules/ before studio:node:link writes into it"
  end

  test "node:test registers the shared hook, not a copy of its own" do
    assert_includes REGISTER.read, "node_modules/.studio-engine/node_test/register.mjs"
    assert_empty Dir[Rails.root.join("test/javascript/support/*hooks*")], "the engine ships the hook"
  end

  # The hook maps "cyvasse/<name>" to app/javascript/cyvasse/<name>.js. The
  # browser resolves the same names through config/importmap.rb, so every pin
  # under the prefix must point at that file, or the tests import other code
  # than the page runs.
  test "the hook's cyvasse prefix agrees with the importmap" do
    assert_includes REGISTER.read, 'cyvasse: "app/javascript/cyvasse/"'

    pins = Rails.application.importmap.packages.select { |name, _| name.start_with?("cyvasse/") }
    assert_not_empty pins
    pins.each do |name, pin|
      assert_equal "#{name}.js", pin.path, "#{name} is pinned to #{pin.path}; the hook maps it to #{name}.js"
      assert Rails.root.join("app/javascript", "#{name}.js").file?, "#{name}.js is missing"
    end
  end
end
