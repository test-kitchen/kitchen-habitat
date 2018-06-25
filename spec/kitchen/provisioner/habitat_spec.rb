require_relative "../../spec_helper"

require "logger"
require "stringio"

require "kitchen/configurable"
require "kitchen/logging"
require "kitchen/provisioner/habitat"
require "kitchen/driver/dummy"
require "kitchen/transport/dummy"
require "kitchen/verifier/dummy"

describe Kitchen::Provisioner::Habitat do

  let(:logged_output) { StringIO.new }
  let(:logger)        { Logger.new(logged_output) }
  let(:config)        { { kitchen_root: "/kroot" } }
  let(:platform)      { Kitchen::Platform.new(name: "fooos-99") }
  let(:suite)         { Kitchen::Suite.new(name: "suitey") }
  let(:verifier)      { Kitchen::Verifier::Dummy.new }
  let(:driver)        { Kitchen::Driver::Dummy.new }
  let(:transport)     { Kitchen::Transport::Dummy.new }
  let(:state_file)    { double("state_file") }
  # let(:state)         { Hash.new }
  # let(:env)           { Hash.new }

  let(:provisioner_object) { Kitchen::Provisioner::Habitat.new(config) }

  let(:provisioner) do
    p = provisioner_object
    instance
    p
  end

  let(:instance) do
    Kitchen::Instance.new(
      verifier:  verifier,
      driver: driver,
      logger: logger,
      suite: suite,
      platform: platform,
      provisioner: provisioner_object,
      transport: transport,
      state_file: state_file
    )
  end

  it "driver api_version is 2" do
    expect(provisioner.diagnose_plugin[:api_version]).to eq(2)
  end
end
