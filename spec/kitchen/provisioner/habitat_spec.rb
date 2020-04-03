require_relative "../../spec_helper"

require "logger"
require "stringio"

require "kitchen/configurable"
require "kitchen/logging"
require "kitchen/provisioner/habitat"
require "kitchen/driver/dummy"
require "kitchen/transport/dummy"
require "kitchen/verifier/dummy"

def wrap_command(code, left_pad_length = 10)
  command = "sh -c '\n"
  command << "TEST_KITCHEN=\"1\"; export TEST_KITCHEN\n"
  command << "CI=\"true\"; export CI\n" if ENV["CI"]
  command << code
  command <<"'"
  command
end

describe Kitchen::Provisioner::Habitat do
  let(:logged_output)   { StringIO.new }
  let(:logger)          { Logger.new(logged_output) }
  let(:lifecycle_hooks) { Kitchen::LifecycleHooks.new({}) }
  let(:config)          { { kitchen_root: "/kroot" } }
  let(:platform)        { Kitchen::Platform.new(name: "fooos-99") }
  let(:suite)           { Kitchen::Suite.new(name: "suitey") }
  let(:verifier)        { Kitchen::Verifier::Dummy.new }
  let(:driver)          { Kitchen::Driver::Dummy.new }
  let(:transport)       { Kitchen::Transport::Dummy.new }
  let(:state_file)      { double("state_file") }

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
      lifecycle_hooks: lifecycle_hooks,
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
      expected_code = <<~EXPECTED
        if command -v hab >/dev/null 2>&1
        then
          echo "Habitat CLI already installed."
        else
          curl -o /tmp/install.sh 'https://raw.githubusercontent.com/habitat-sh/habitat/master/components/hab/install.sh'
          sudo -E bash /tmp/install.sh
        fi
      EXPECTED
      expect(install_command).to eq(wrap_command(expected_code, 8))
    end

    it "generates a valid install script with accepted license" do
      config[:hab_license] = "accept"
      install_command = provisioner.send(
        :install_command
      )
      expected_code = <<~EXPECTED
        export HAB_LICENSE=accept
        if command -v hab >/dev/null 2>&1
        then
          echo "Habitat CLI already installed."
        else
          curl -o /tmp/install.sh 'https://raw.githubusercontent.com/habitat-sh/habitat/master/components/hab/install.sh'
          sudo -E bash /tmp/install.sh
        fi
      EXPECTED
      expect(install_command).to eq(wrap_command(expected_code, 8))
    end
  end

  describe "#init_command" do
    it "generates a valid initialization script" do
      install_command = provisioner.send(
        :init_command
      )
      expected_code = <<~EXPECTED
        id -u hab >/dev/null 2>&1 || sudo -E useradd hab >/dev/null 2>&1
        rm -rf /tmp/kitchen
        mkdir -p /tmp/kitchen/results
        mkdir -p /tmp/kitchen/config
      EXPECTED
      expect(install_command).to eq(wrap_command(expected_code))
    end

    it "removes the config creation line when an override is present" do
      config[:override_package_config] = true
      install_command = provisioner.send(
        :init_command
      )
      expected_code = <<~EXPECTED
        id -u hab >/dev/null 2>&1 || sudo -E useradd hab >/dev/null 2>&1
        rm -rf /tmp/kitchen
        mkdir -p /tmp/kitchen/results
      EXPECTED
      expect(install_command).to eq(wrap_command(expected_code))
    end
  end

  describe "#export_hab_bldr_url" do
    it "sets the HAB_BLDR_URL env var when config[:depot_url] is set" do
      config[:depot_url] = "https://bldr.cthulhu.com"
      bldr_export = provisioner.send(
        :export_hab_bldr_url
      )
      expect(bldr_export).to eq("export HAB_BLDR_URL=https://bldr.cthulhu.com")
    end

    it "should return nil if config[:depot_url] is not set" do
      bldr_export = provisioner.send(
        :export_hab_bldr_url
      )
      expect(bldr_export).to eq(nil)
    end
  end

  describe "#supervisor_options" do
    it "sets the --listen-ctl flag when config[:hab_sup_listen_ctl] is set" do
      config[:hab_sup_listen_ctl] = "0.0.0.0:9632"
      supervisor_options = provisioner.send(
        :supervisor_options
      )
      expect(supervisor_options).to include("--listen-ctl 0.0.0.0:9632")
    end

    it "doesn't set the --listen-ctl flag when config[:hab_sup_listen_ctl] is unset" do
      supervisor_options = provisioner.send(
        :supervisor_options
      )
      expect(supervisor_options).not_to include("--listen-ctl 0.0.0.0:9632")
    end

    it "sets the --ring flag when config[:hab_sup_ring] is set" do
      config[:hab_sup_ring] = "test"
      supervisor_options = provisioner.send(
        :supervisor_options
      )
      expect(supervisor_options).to include("--ring test")
    end

    it "doesn't set the --ring flag when config[:hab_sup_ring] is unset" do
      supervisor_options = provisioner.send(
        :supervisor_options
      )
      expect(supervisor_options).not_to include("--ring test")
    end
  end
end
