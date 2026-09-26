require "open3"

# Finds merge-conflict markers left in committed files. README.md on
# `accepted` once carried a whole conflict (commit 0b32e5e) through review
# and CI; test/lib/conflict_markers_test.rb now fails the build on one.
#
# A marker is a line that starts with seven `<` or seven `>` followed by a
# space or the end of the line, exactly as git writes them. The `=======`
# separator alone is not flagged: it is also a Markdown heading underline.
module ConflictMarkers
  MARKER = /\A(?:<{7}|>{7})(?: |\r?\n|\z)/

  # [[path, line number], ...] for every marker in `paths` (relative to
  # `root`). Binary files (any NUL byte) are skipped.
  def self.scan(paths, root:)
    paths.flat_map do |path|
      full = File.join(root, path)
      next [] unless File.file?(full)

      content = File.binread(full)
      next [] if content.include?("\0")

      content.each_line.with_index(1).filter_map { |line, number| [ path, number ] if line.match?(MARKER) }
    end
  end

  # Every file git tracks under `root`.
  def self.tracked_files(root)
    out, status = Open3.capture2("git", "ls-files", "-z", chdir: root.to_s)
    raise "git ls-files failed in #{root}" unless status.success?

    out.split("\0")
  end
end
