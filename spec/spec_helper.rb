require "rspec"
require "gitlab_monitor"

require "open3"
require "tmpdir"

class GitRepoBuilder
  def origin
    @origin ||= create_origin
  end

  def cloned_repo
    @cloned_repo ||= clone_origin
  end

  def cleanup
    FileUtils.rm_r(@origin) if @origin
    FileUtils.rm_r(@cloned_repo) if @cloned_repo
  end

  private

  def create_origin
    path = Dir.mktmpdir
    Open3.capture3("git init", chdir: path)
    Open3.capture3("git commit --allow-empty -m 'Beep'", chdir: path)
    Open3.capture3("git checkout -b other", chdir: path)
    path
  end

  def clone_origin
    path = Dir.mktmpdir
    Dir.rmdir(path)
    Open3.capture3("git clone #{origin} #{path}")
    Open3.capture3("git checkout master", chdir: path)
    path
  end
end

GitProberOptions = Struct.new(:source, :labels)

class CLIArgs
  def initialize(args)
    @arguments = args
  end

  def options
    yield self
  end

  def on(*args)
  end

  def banner=(banner)
  end

  def parse!
    @arguments
  end
end
