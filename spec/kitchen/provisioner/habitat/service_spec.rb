# frozen_string_literal: true

require "kitchen/provisioner/habitat"
require "fakefs/safe"

RSpec.describe Kitchen::Provisioner::Habitat do
  include_context "habitat provisioner"

  describe "#service_options" do
    it "sets the --bind flag when config[:hab_sup_bind] is set with a single binding" do
      config[:hab_sup_bind] = ["database:database.default"]
      service_options = provisioner.send(
        :service_options
      )
      expect(service_options).to include("--bind database:database.default")
    end

    it "sets the --bind flag when config[:hab_sup_bind] is set with multiple bindings" do
      config[:hab_sup_bind] = ["web:web.default", "database:database.default"]
      service_options = provisioner.send(
        :service_options
      )
      expect(service_options).to include("--bind web:web.default  --bind database:database.default")
    end

    it "doesn't set the --bind flag when config[:hab_sup_bind] is unset" do
      service_options = provisioner.send(
        :service_options
      )
      expect(service_options).not_to include("--bind test")
    end

    it "sets the --group flag when config[:hab_sup_group] is set" do
      config[:hab_sup_group] = "test"
      service_options = provisioner.send(
        :service_options
      )
      expect(service_options).to include("--group test")
    end

    it "doesn't set the --ring flag when config[:hab_sup_group] is unset" do
      service_options = provisioner.send(
        :service_options
      )
      expect(service_options).not_to include("--group test")
    end

    it "sets the --topology flag when config[:service_topology] is set" do
      config[:service_topology] = "standalone"
      service_options = provisioner.send(
        :service_options
      )
      expect(service_options).to include("--topology standalone")
    end

    it "doesn't set the --topology flag when config[:service_topology] is unset" do
      service_options = provisioner.send(
        :service_options
      )
      expect(service_options).not_to include("--topology standalone")
    end

    it "sets the --strategy flag when config[:service_update_strategy] is set" do
      config[:service_update_strategy] = "at-once"
      service_options = provisioner.send(
        :service_options
      )
      expect(service_options).to include("--strategy at-once")
    end

    it "doesn't set the --strategy flag when config[:service_update_strategy] is unset" do
      service_options = provisioner.send(
        :service_options
      )
      expect(service_options).not_to include("--strategy at-once")
    end

    it "sets the --channel flag when config[:channel] is set" do
      config[:channel] = "staging"
      service_options = provisioner.send(
        :service_options
      )
      expect(service_options).to include("--channel staging")
    end

    it "doesn't set the --channel flag when config[:channel] is unset" do
      service_options = provisioner.send(
        :service_options
      )
      expect(service_options).not_to include("--channel staging")
    end
  end

  describe "#package_ident" do
    it "should assemble the full ident " do
      config[:package_origin] = "example"
      config[:package_name] = "package"
      config[:package_version] = "0.1.0"
      config[:package_release] = "20200406205105"
      package_ident = provisioner.send(
        :package_ident
      )
      expect(package_ident).to eq("example/package/0.1.0/20200406205105")
    end
  end

  describe "#get_artifact_name" do
    describe "for windows operating systems" do
      before { allow(platform).to receive(:os_type).and_return("windows") }
      it "should resolve the target artifact name" do
        config[:artifact_name] = "example-package-0.1.0-20200406205105-x86_64-linux.hart"
        get_artifact_name = provisioner.send(
          :get_artifact_name
        )
        expect(get_artifact_name).to eq("$env:TEMP\\kitchen/results/example-package-0.1.0-20200406205105-x86_64-linux.hart")
      end
    end
    describe "for windows operating systems" do
      before { allow(platform).to receive(:os_type).and_return("linux") }
      it "should resolve the target artifact name" do
        config[:artifact_name] = "example-package-0.1.0-20200406205105-x86_64-linux.hart"
        get_artifact_name = provisioner.send(
          :get_artifact_name
        )
        expect(get_artifact_name).to eq("/tmp/kitchen/results/example-package-0.1.0-20200406205105-x86_64-linux.hart")
      end
    end
  end
end
