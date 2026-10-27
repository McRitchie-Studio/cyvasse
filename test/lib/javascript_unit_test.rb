require "test_helper"
require "open3"

# [unit] Runs bin/test-js (the game engine's node:test files) inside the Rails
# suite. The shared importmap hook lives in the studio-engine gem, which only a
# bundled lane has, so the hub's bundle-free `javascript` lane cannot run it
# (ci.yml turns that lane off). bin/test-js fails a Node major other than the
# one .tool-versions pins.
class JavascriptUnitTest < ActiveSupport::TestCase
  test "the JavaScript unit tests pass on the pinned Node" do
    Studio::NodeTooling.link!(Rails.root)

    output, status = Open3.capture2e(Rails.root.join("bin/test-js").to_s, chdir: Rails.root.to_s)

    assert status.success?, output
    assert_match(/^# pass [1-9]/, output, "node ran no test")
    assert_match(/^# fail 0$/, output)
  end
end
