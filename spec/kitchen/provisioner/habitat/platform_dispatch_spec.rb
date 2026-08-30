# frozen_string_literal: true

require "kitchen/provisioner/habitat"

# Every command this provisioner produces branches on the platform. These
# examples pin which branch each entry point takes, so a change to
# windows_os? detection cannot quietly send Windows instances a bash script.
RSpec.describe Kitchen::Provisioner::Habitat do
  include_context "habitat provisioner"

  let(:config) { { kitchen_root: "/kroot", root_path: "/tmp/kitchen", package_name: "redis" } }

  shared_examples "a platform-dispatched command" do |method, windows_marker, linux_marker|
    it "produces the Windows form on Windows" do
      allow(platform).to receive(:os_type).and_return("windows")

      command = provisioner.public_send(method)

      expect(command).to include(windows_marker)
      expect(command).not_to include(linux_marker)
    end

    it "produces the Linux form everywhere else" do
      allow(platform).to receive(:os_type).and_return("linux")

      command = provisioner.public_send(method)

      expect(command).to include(linux_marker)
      expect(command).not_to include(windows_marker)
    end
  end

  describe "#install_command" do
    include_examples "a platform-dispatched command",
      :install_command,
      "Set-ExecutionPolicy Bypass",
      "command -v hab"

    it "passes hab_version to the Linux install script when one is pinned" do
      allow(platform).to receive(:os_type).and_return("linux")
      config[:hab_version] = "1.6.652"

      expect(provisioner.install_command).to include("bash /tmp/install.sh -v 1.6.652")
    end

    it "passes no version to the Linux install script when it is 'latest'" do
      allow(platform).to receive(:os_type).and_return("linux")

      expect(provisioner.install_command).to include("bash /tmp/install.sh\n")
      expect(provisioner.install_command).not_to include("-v latest")
    end

    it "passes the channel and version to the Windows install script" do
      allow(platform).to receive(:os_type).and_return("windows")
      config[:hab_channel] = "unstable"
      config[:hab_version] = "1.6.652"

      expect(provisioner.install_command).to include("-ArgumentList unstable, 1.6.652")
    end
  end

  describe "#init_command" do
    include_examples "a platform-dispatched command",
      :init_command,
      "core/windows-service",
      "/etc/systemd/system/hab-sup.service"

    it "creates the config staging directory unless the package config is overridden" do
      allow(platform).to receive(:os_type).and_return("linux")

      expect(provisioner.init_command).to include("mkdir -p /tmp/kitchen/config")
    end

    it "leaves the config staging directory to the sandbox upload when overriding" do
      allow(platform).to receive(:os_type).and_return("linux")
      config[:override_package_config] = true

      expect(provisioner.init_command).not_to include("mkdir -p /tmp/kitchen/config")
    end
  end

  describe "#prepare_command" do
    it "removes the previous user.toml before installing the new one" do
      allow(platform).to receive(:os_type).and_return("linux")
      config[:config_directory] = "configs"
      allow(File).to receive(:exist?).and_call_original
      allow(File).to receive(:exist?).with("/kroot/configs/user.toml").and_return(true)

      command = provisioner.prepare_command

      expect(command.index("find /hab/user/redis/config -name user.toml -delete"))
        .to be < command.index("cp /tmp/kitchen/config/user.toml /hab/user/redis/config/user.toml")
    end

    it "still clears a stale user.toml when no config_directory is configured" do
      allow(platform).to receive(:os_type).and_return("linux")

      command = provisioner.prepare_command

      expect(command).to include("find /hab/user/redis/config -name user.toml -delete")
      expect(command).not_to include("cp /tmp/kitchen/config/user.toml")
    end
  end

  describe "#run_command" do
    it "works around the Windows hart landing outside the results directory" do
      allow(platform).to receive(:os_type).and_return("windows")
      config[:artifact_name] = "mycorp-wildfly-26.1.1-20240115194501-x86_64-linux.hart"

      expect(provisioner.run_command)
        .to include("hab pkg install /tmp/kitchen/mycorp-wildfly-26.1.1-20240115194501-x86_64-linux.hart")
      expect(provisioner.run_command).not_to include("/tmp/kitchen/results/")
    end

    it "prepends the Habitat directory to PATH on Windows" do
      allow(platform).to receive(:os_type).and_return("windows")

      expect(provisioner.run_command).to include('$env:Path += ";C:\\ProgramData\\Habitat"')
    end

    it "waits for the supervisor before installing anything on Linux" do
      allow(platform).to receive(:os_type).and_return("linux")

      command = provisioner.run_command

      expect(command.index("Waiting 5 seconds for supervisor to finish loading"))
        .to be < command.index("hab pkg install")
    end
  end
end
