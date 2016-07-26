Gem::Specification.new do |s|
  s.name          = "gitlab-monitoring"
  s.version       = "0.0.1"
  s.date          = "2016-07-27"
  s.summary       = "GitLab monitoring tools"
  s.description   = "GitLab monitoring tools"
  s.authors       = ["Pablo Carranza"]
  s.email         = "pablo@gitlab.com"
  s.files         = `git ls-files -z`.split("\x0")
  s.require_paths = ["lib"]
  s.executables   = spec.files.grep(%r{^bin/}) { |f| File.basename(f) }
  s.test_files    = spec.files.grep(%r{^(test|spec|features)/})
  s.homepage      = "http://gitlab.com"
  s.license       = "MIT"
end
