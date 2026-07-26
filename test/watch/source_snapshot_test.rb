# frozen_string_literal: true

require_relative "../test_helper"
require "tmpdir"

class WatchSourceSnapshotTest < Minitest::Test
  def test_detects_same_size_content_changes_even_when_mtime_is_restored
    Dir.mktmpdir("ibex-watch-snapshot") do |directory|
      path = File.join(directory, "parser.y")
      File.binwrite(path, "AAAA")
      original_time = File.mtime(path)
      before = Ibex::Watch::SourceSnapshot.new([path])
      File.binwrite(path, "BBBB")
      File.utime(original_time, original_time, path)

      refute_equal before, Ibex::Watch::SourceSnapshot.new([path])
    end
  end

  def test_detects_relative_symlink_exchange_and_dangling_target_creation
    Dir.mktmpdir("ibex-watch-snapshot") do |directory|
      first = File.join(directory, "first.y")
      second = File.join(directory, "second.y")
      link = File.join(directory, "parser.y")
      File.binwrite(first, "grammar")
      File.binwrite(second, "grammar")
      File.symlink("first.y", link)
      initial = Ibex::Watch::SourceSnapshot.new([link])
      File.unlink(link)
      File.symlink("second.y", link)
      exchanged = Ibex::Watch::SourceSnapshot.new([link])
      refute_equal initial, exchanged

      File.unlink(second)
      dangling = Ibex::Watch::SourceSnapshot.new([link])
      File.binwrite(second, "grammar")
      refute_equal dangling, Ibex::Watch::SourceSnapshot.new([link])
    end
  end

  def test_detects_intermediate_symlink_retarget_with_the_same_file_inode
    Dir.mktmpdir("ibex-watch-snapshot") do |directory|
      first = File.join(directory, "first")
      second = File.join(directory, "second")
      link = File.join(directory, "link")
      Dir.mkdir(first)
      Dir.mkdir(second)
      File.binwrite(File.join(first, "part.y"), "fragment")
      File.link(File.join(first, "part.y"), File.join(second, "part.y"))
      File.symlink("first", link)
      path = File.join(link, "part.y")
      before = Ibex::Watch::SourceSnapshot.new([path])
      File.unlink(link)
      File.symlink("second", link)

      refute_equal before, Ibex::Watch::SourceSnapshot.new([path])
    end
  end
end
