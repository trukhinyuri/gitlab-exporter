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
  s.homepage      = "http://gitlab.com"
  s.license       = "MIT"

  s.add_runtime_dependency "connection_pool", "2.2.5"
  s.add_runtime_dependency "faraday", "~> 1.8.0"
  s.add_runtime_dependency "pg", "1.5.3"
  s.add_runtime_dependency "puma", "5.6.5"
  s.add_runtime_dependency "quantile", "0.2.1"
  s.add_runtime_dependency "redis", "4.4.0"
  s.add_runtime_dependency "redis-namespace", "1.9.0"
  s.add_runtime_dependency "sidekiq", "6.4.0"
  s.add_runtime_dependency "sinatra", "~> 2.2.0"
  s.add_runtime_dependency "webrick", "~> 1.7"

  s.add_development_dependency "rspec", "~> 3.7.0"
  s.add_development_dependency "rspec-expectations", "~> 3.7.0"
end
