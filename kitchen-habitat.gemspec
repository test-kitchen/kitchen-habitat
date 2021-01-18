$LOAD_PATH.unshift File.expand_path("lib", __dir__)
require "kitchen-habitat/version"

Gem::Specification.new do |s|
  s.name              = "kitchen-habitat"
  s.version           = Kitchen::Habitat::VERSION
  s.authors           = ["Steven Murawski", "Robb Kidd"]
  s.email             = ["steven.murawski@gmail.com", "robb@thekidds.org"]
  s.homepage          = "https://github.com/test-kitchen/kitchen-habitat"
  s.summary           = "Habitat provisioner for test-kitchen"
  candidates          = Dir.glob("lib/**/*") + ["README.md"]
  s.files             = candidates.sort
  s.require_paths     = ["lib"]
  s.license           = "Apache-2.0"
  s.description       = <<~EOF
    == DESCRIPTION:

    Habitat Provisioner for Test Kitchen

    == FEATURES:

    TBD

  EOF
  
  s.required_ruby_version = ">= 2.5"
  
  s.add_dependency "test-kitchen", ">= 1.4", "< 3"
end
