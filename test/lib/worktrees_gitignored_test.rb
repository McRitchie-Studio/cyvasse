require "test_helper"
require "open3"

# [unit] bin/agent-worktree creates <repo>/.worktrees/ in every repo it manages
# or discovers. Untracked, it leaves the primary checkout permanently dirty.
class WorktreesGitignoredTest < ActiveSupport::TestCase
  test ".worktrees/ is ignored by git" do
    _out, _err, status = Open3.capture3("git", "check-ignore", "-q", ".worktrees/some-desk/file.rb",
                                        chdir: Rails.root.to_s)

    assert status.success?, ".gitignore must ignore /.worktrees/ (new-app-onboarding-sop.md section 1)"
  end
end
