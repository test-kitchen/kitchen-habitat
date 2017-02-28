$LOAD_PATH.unshift File.expand_path("../lib", __FILE__)
require "kitchen-habitat/version"

Gem::Specification.new do |s|
  s.name              = "kitchen-habitat"
  s.version           = Kitchen::Habitat::VERSION
  s.authors           = ["Steven Murawski"]
  s.email             = ["smurawski@chef.io"]
  s.homepage          = "https://github.com/test-kitchen/kitchen-habitat"
  s.summary           = "Habitat provisioner for test-kitchen"
  candidates          = Dir.glob("lib/**/*") + ["README.md", "kitchen-habitat.gemspec"]
  s.files             = candidates.sort
  s.platform          = Gem::Platform::RUBY
  s.require_paths     = ["lib"]
  s.rubyforge_project = "[none]"
  s.license           = "Apache 2"
  s.description       = <<-EOF
== DESCRIPTION:

Habitat Provisioner for Test Kitchen

== FEATURES:

TBD

EOF
  s.add_dependency "test-kitchen", "~> 1.4"

  s.add_development_dependency "countloc", "~> 0.4"
  s.add_development_dependency "rake"
  s.add_development_dependency "rspec",     "~> 3.2"
  s.add_development_dependency "simplecov", "~> 0.9"

  # style and complexity libraries are tightly version pinned as newer releases
  # may introduce new and undesireable style choices which would be immediately
  # enforced in CI
  s.add_development_dependency "chefstyle"
end
