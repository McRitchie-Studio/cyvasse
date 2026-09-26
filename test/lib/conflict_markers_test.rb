require "test_helper"
require "tmpdir"

# [unit] CI fails when a committed file still carries a merge-conflict
# marker (README.md reached `accepted` with one in 0b32e5e).
class ConflictMarkersTest < ActiveSupport::TestCase
  # Built, not written out, so this file never holds a marker itself.
  OURS = "#{'<' * 7} HEAD"
  THEIRS = "#{'>' * 7} feat/other"

  test "no tracked file carries a merge-conflict marker" do
    found = ConflictMarkers.scan(ConflictMarkers.tracked_files(Rails.root), root: Rails.root)

    assert_empty found, "resolve the merge-conflict markers at: #{found.map { _1.join(':') }.join(', ')}"
  end

  test "flags both marker lines of a conflict, and nothing in a clean file" do
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, "conflicted.md"), "# Title\n#{OURS}\nours\n=======\ntheirs\n#{THEIRS}\n")
      File.write(File.join(dir, "clean.md"), "Heading\n=======\n\nA line with #{'<' * 7} inside it.\n")

      assert_equal [ [ "conflicted.md", 2 ], [ "conflicted.md", 6 ] ],
                   ConflictMarkers.scan(%w[conflicted.md clean.md], root: dir)
      assert_empty ConflictMarkers.scan(%w[clean.md], root: dir)
    end
  end

  test "a marker on the last line with no newline is still flagged; binary files are skipped" do
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, "tail.rb"), "x = 1\n#{THEIRS.split.first}")
      File.binwrite(File.join(dir, "image.png"), "\x89PNG\0\n#{OURS}\n")

      assert_equal [ [ "tail.rb", 2 ] ], ConflictMarkers.scan(%w[tail.rb image.png missing.txt], root: dir)
    end
  end
end
