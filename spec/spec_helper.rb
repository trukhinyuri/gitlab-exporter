require "rspec"
require "gitlab_monitor"

require "open3"
require "tmpdir"

class GitRepoBuilder
  def origin
    @origin ||= create_origin
  end

  def clone
    @clone ||= create_clone
  end

  def cleanup
    FileUtils.rm_r(@origin) if @origin
    FileUtils.rm_r(@clone) if @clone
  end

  private

  def create_origin
    path = Dir.mktmpdir
    Open3.capture3("git init", chdir: path)
    Open3.capture3("git commit --allow-empty -m 'Beep'", chdir: path)
    Open3.capture3("git checkout -b other", chdir: path)
    path
  end

  def create_clone
    path = Dir.mktmpdir
    Dir.rmdir(path)
    Open3.capture3("git clone #{origin} #{path}")
    Open3.capture3("git checkout master", chdir: path)
    path
  end
end
