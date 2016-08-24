lib = File.expand_path("../lib", __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require "gitlab_monitor/version"

Gem::Specification.new do |s|
  s.name          = "gitlab-monitor"
  s.version       = GitLab::Monitor::VERSION
  s.date          = "2016-07-27"
  s.summary       = "GitLab monitoring tools"
  s.description   = "GitLab monitoring tools to use with prometheus"
  s.authors       = ["Pablo Carranza"]
  s.email         = "pablo@gitlab.com"

  s.files         = `git ls-files -z`.split("\x0")

  s.executables   = ["gitlab-mon"]
  s.test_files    = s.files.grep(%r{^(spec)/})

  s.require_paths = ["lib"]
  s.homepage      = "http://gitlab.com"
  s.license       = "MIT"

  s.add_runtime_dependency "pg", "~> 0.18.4"

  s.add_development_dependency "rspec", "~> 3.3"
end
