lib = File.expand_path("lib", __dir__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require "gitlab_exporter/version"

Gem::Specification.new do |s|
  s.name          = "gitlab-exporter"
  s.version       = GitLab::Exporter::VERSION
  s.date          = "2016-07-27"
  s.summary       = "GitLab metrics exporter"
  s.description   = "GitLab metrics exporter to use with prometheus"
  s.authors       = ["Pablo Carranza"]
  s.email         = "pablo@gitlab.com"

  s.files         = `git ls-files -z`.split("\x0")

  s.executables   = ["gitlab-exporter"]
  s.test_files    = s.files.grep(%r{^(spec)/})

  s.require_paths = ["lib"]
  s.homepage      = "https://gitlab.com/gitlab-org/ruby/gems/gitlab-exporter"
  s.license       = "MIT"

  s.add_runtime_dependency "connection_pool", "2.2.5"
  s.add_runtime_dependency "deep_merge", "~> 1.2.2"
  # Lock to 2.8.1 until RubyGems 3.5.5 is shipped with the fix for
  # https://github.com/rubygems/rubygems/issues/7374
  s.add_runtime_dependency "faraday", [">= 1.8.0", "<= 2.8.1"]
  s.add_runtime_dependency "pg", "1.5.9"
  s.add_runtime_dependency "puma", "5.6.8"
  s.add_runtime_dependency "quantile", "0.2.1"
  s.add_runtime_dependency "redis", "4.5.0"
  s.add_runtime_dependency "redis-namespace", "1.9.0"
  s.add_runtime_dependency "sidekiq", "6.5.12"
  s.add_runtime_dependency "sinatra", "~> 2.2.0"
  s.add_runtime_dependency "webrick", "~> 1.7"

  s.add_development_dependency "rspec", "~> 3.12.0"
  s.add_development_dependency "rspec-expectations", "~> 3.12.0"
end
