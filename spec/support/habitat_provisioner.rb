# frozen_string_literal: true

require "logger"
require "stringio" unless defined?(StringIO)

require "kitchen/configurable"
require "kitchen/logging"
require "kitchen/driver/dummy"
require "kitchen/transport/dummy"
require "kitchen/verifier/dummy"

# Wires up a Habitat provisioner attached to a real Kitchen::Instance.
#
# Every provisioner spec needs the same scaffolding, and several of the
# methods under test reach through `instance` for the platform name or the
# driver's config, so a bare provisioner is not enough.
RSpec.shared_context "habitat provisioner" do
  let(:logged_output)   { StringIO.new }
  let(:logger)          { Logger.new(logged_output) }
  let(:config)          { { kitchen_root: "/kroot" } }
  let(:platform)        { Kitchen::Platform.new(name: "fooos-99") }
  let(:suite)           { Kitchen::Suite.new(name: "suitey") }
  let(:verifier)        { Kitchen::Verifier::Dummy.new }
  let(:driver)          { Kitchen::Driver::Dummy.new }
  let(:transport)       { Kitchen::Transport::Dummy.new }
  let(:state_file)      { double("state_file") }
  let(:lifecycle_hooks) { Kitchen::LifecycleHooks.new(config, state_file) }

  let(:provisioner_object) { Kitchen::Provisioner::Habitat.new(config) }

  let(:provisioner) do
    p = provisioner_object
    instance
    p
  end

  let(:instance) do
    Kitchen::Instance.new(
      verifier: verifier,
      driver: driver,
      logger: logger,
      lifecycle_hooks: lifecycle_hooks,
      suite: suite,
      platform: platform,
      provisioner: provisioner_object,
      transport: transport,
      state_file: state_file
    )
  end
end
