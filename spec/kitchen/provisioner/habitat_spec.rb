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

  describe "#install_command" do
    it "generates a valid install script" do
      install_command = provisioner.send(
        :install_command
      )
      expect(install_command).to eq("sh -c '\nTEST_KITCHEN=\"1\"; export TEST_KITCHEN\n        \n        if command -v hab >/dev/null 2>&1\n        then\n          echo \"Habitat CLI already installed.\"\n        else\n          curl 'https://raw.githubusercontent.com/habitat-sh/habitat/master/components/hab/install.sh' | sudo -E bash\n        fi\n'")
    end
  end

  describe "#init_command" do
    it "generates a valid initialization script" do
      install_command = provisioner.send(
        :init_command
      )
      expect(install_command).to eq("sh -c '\nTEST_KITCHEN=\"1\"; export TEST_KITCHEN\n          id -u hab >/dev/null 2>&1 || sudo -E useradd hab >/dev/null 2>&1\n          rm -rf /tmp/kitchen\n          mkdir -p /tmp/kitchen/results\n          mkdir -p /tmp/kitchen/config\n'")
    end

    it "removes the config creation line when an override is present" do
      config[:override_package_config] = true
      install_command = provisioner.send(
        :init_command
      )
      expect(install_command).to eq("sh -c '\nTEST_KITCHEN=\"1\"; export TEST_KITCHEN\n          id -u hab >/dev/null 2>&1 || sudo -E useradd hab >/dev/null 2>&1\n          rm -rf /tmp/kitchen\n          mkdir -p /tmp/kitchen/results\n          \n'")
    end
  end
end
