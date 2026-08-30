# frozen_string_literal: true

require "kitchen/provisioner/habitat"
require "fakefs/safe"

RSpec.describe Kitchen::Provisioner::Habitat do
  include_context "habitat provisioner"

  let(:config) { { kitchen_root: "/kroot", root_path: "/tmp/kitchen" } }

  describe "#run_command" do
    context "on Linux" do
      before { allow(platform).to receive(:os_type).and_return("linux") }

      it "installs and loads the configured package identifier" do
        config[:package_origin] = "core"
        config[:package_name] = "redis"

        command = provisioner.run_command

        expect(command).to include("sudo hab pkg install core/redis --channel stable --force")
        expect(command).to include("sudo -E hab svc load core/redis")
      end

      it "installs the uploaded artifact but loads the identifier parsed from its name" do
        config[:artifact_name] = "core-redis-4.0.14-20240106065001-x86_64-linux.hart"

        command = provisioner.run_command

        expect(command).to include("sudo hab pkg install /tmp/kitchen/results/core-redis-4.0.14-20240106065001-x86_64-linux.hart")
        expect(command).to include("sudo -E hab svc load core/redis")
      end

      # The supervisor accepts a run hook in either place: hooks/run from a
      # hook template, or a run file in the package root from pkg_svc_run.
      # Only hooks/run used to be checked, so a package built the second way
      # -- core/redis, among many others -- was installed and then silently
      # never loaded, and the converge reported success.
      it "guards the load with a test for a run hook in either place" do
        config[:package_name] = "redis"

        command = provisioner.run_command

        expect(command).to include(%(pkg_path="$(sudo hab pkg path core/redis)"))
        expect(command).to include(%(if [ -f "$pkg_path/hooks/run" ] || [ -f "$pkg_path/run" ]))
      end

      it "asks hab for the package path only once" do
        config[:package_name] = "redis"

        expect(provisioner.run_command.scan("hab pkg path").length).to eq(1)
      end

      # The timeout used to be spelled `[$timer -gt 300]` with no spaces, which
      # bash parses as a command named `[0`, and the counter was incremented
      # with `$timer++`, which bash parses as a command named `0++`. Both were
      # "command not found" every iteration, so the loop never timed out and a
      # service that failed to load hung the converge forever.
      it "increments the wait counter with valid shell arithmetic" do
        config[:package_name] = "redis"

        command = provisioner.run_command

        expect(command).to include("timer=$((timer + 1))")
        expect(command).not_to include("$timer++")
      end

      it "spells the timeout comparison as a valid test expression" do
        config[:package_name] = "redis"
        config[:service_load_timeout] = 42

        command = provisioner.run_command

        expect(command).to include(%(if [ "$timer" -ge 42 ]; then))
        expect(command).not_to include("[$timer")
      end

      it "says what it timed out waiting for before exiting non-zero" do
        config[:package_name] = "redis"
        config[:service_load_timeout] = 42

        command = provisioner.run_command

        expect(command).to include("Timed out after 42s waiting for core/redis to load")
        expect(command).to include("exit 1")
      end

      it "generates a syntactically valid bash script" do
        config[:package_name] = "redis"
        config[:hab_sup_bind] = ["database:postgresql.default"]

        expect(bash_syntax_ok?(provisioner.run_command)).to be true
      end

      it "passes the service options through to hab svc load" do
        config[:package_name] = "redis"
        config[:hab_sup_group] = "prod"
        config[:service_topology] = "leader"

        expect(provisioner.run_command).to include("--group prod").and include("--topology leader")
      end
    end

    context "on Windows" do
      before { allow(platform).to receive(:os_type).and_return("windows") }

      it "installs and loads the configured package identifier" do
        config[:package_name] = "redis"

        command = provisioner.run_command

        expect(command).to include("hab pkg install core/redis --channel stable --force")
        expect(command).to include("hab svc load core/redis")
      end

      it "honours the configured service_load_timeout" do
        config[:package_name] = "redis"
        config[:service_load_timeout] = 42

        expect(provisioner.run_command).to include("if ($timer -gt 42){exit 1}")
      end

      it "guards the load with a test for a run hook in either place" do
        config[:package_name] = "redis"

        command = provisioner.run_command

        expect(command).to include("$PkgPath = hab pkg path core/redis")
        expect(command).to include(%(@("hooks\\run", "hooks\\run.ps1", "run", "run.ps1")))
      end
    end
  end

  describe "#install_command" do
    it "generates a syntactically valid bash script on Linux" do
      allow(platform).to receive(:os_type).and_return("linux")

      expect(bash_syntax_ok?(provisioner.install_command)).to be true
    end
  end

  describe "#init_command" do
    it "generates a syntactically valid bash script on Linux" do
      allow(platform).to receive(:os_type).and_return("linux")
      config[:depot_url] = "https://bldr.example.com"
      config[:hab_license] = "accept"
      config[:hab_sup_version] = "1.6.652"

      expect(bash_syntax_ok?(provisioner.init_command)).to be true
    end
  end

  describe "#prepare_command" do
    it "generates a syntactically valid bash script on Linux" do
      allow(platform).to receive(:os_type).and_return("linux")
      config[:package_name] = "redis"

      expect(bash_syntax_ok?(provisioner.prepare_command)).to be true
    end
  end
end
