#!/usr/bin/env ruby

class GitRunner
  def initialize(repo)
    @repo = repo
    @tracker = TimeTracker.new
  end

  def pull
    in_repo { @tracker.track { `git pull -q` } }
  end

  def push
    in_repo {
      `git commit --allow-empty -m "Beep"`
      @tracker.track { `git push -q` }
    }
  end

  private

  def in_repo
    Dir.chdir(@repo) { yield }
  end
end

class PrometheusMetrics
  def initialize
    @metrics = {}
  end

  def add(name, value, **labels)
    @metrics[name] = { value: value, labels: labels, timestamp: (Time.now.to_f * 1000).to_i}
  end

  def to_s
    buffer = StringIO.new
    @metrics.each { |name, metrics|
      buffer.write("#{name}")
      labels = (metrics[:labels] || {}).map { |label, value| "#{label}=\"#{value}\"" }.join(",")
      buffer.write("{#{labels}}") unless labels.empty?
      buffer.write(" #{metrics[:value]} #{metrics[:timestamp]}\n")
    }
    buffer.rewind
    buffer.read
  end
end

def main
  runner = GitRunner.new(File.expand_path("~/dev/emptyness"))
  metrics = PrometheusMetrics.new
  metrics.add "git_pull_time_milliseconds", (runner.pull * 1000).to_i, repo: "emptyness"
  metrics.add "git_push_time_milliseconds", (runner.push * 1000).to_i, repo: "emptyness"
  File.open(File.expand_path("~/metrics/git.prom"), "w") do |prom|
    prom.write(metrics.to_s)
  end
end

main() if __FILE__ == $0
