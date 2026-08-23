# frozen_string_literal: true

require "kitchen/provisioner/habitat"
require "fakefs/safe"

RSpec.describe Kitchen::Provisioner::Habitat do
  include_context "habitat provisioner"

  let(:config) { { kitchen_root: "/kroot", root_path: "/tmp/kitchen" } }

  describe "#hab_sup_ident" do
    it "is the stock supervisor when nothing is configured" do
      expect(provisioner.send(:hab_sup_ident)).to eq("core/hab-sup")
    end

    it "includes the version when one is pinned" do
      config[:hab_sup_version] = "1.6.652"
      expect(provisioner.send(:hab_sup_ident)).to eq("core/hab-sup/1.6.652")
    end

    it "includes the release when one is pinned" do
      config[:hab_sup_version] = "1.6.652"
      config[:hab_sup_release] = "20240115194501"
      expect(provisioner.send(:hab_sup_ident)).to eq("core/hab-sup/1.6.652/20240115194501")
    end

    it "honours a custom origin and name" do
      config[:hab_sup_origin] = "mycorp"
      config[:hab_sup_name] = "sup"
      expect(provisioner.send(:hab_sup_ident)).to eq("mycorp/sup")
    end

    it "drops a release with no version rather than emitting an empty part" do
      config[:hab_sup_release] = "20240115194501"
      expect(provisioner.send(:hab_sup_ident)).to eq("core/hab-sup/20240115194501")
    end
  end

  describe "#custom_supervisor?" do
    it "is false for the stock supervisor" do
      expect(provisioner.send(:custom_supervisor?)).to be false
    end

    it "is true when an artifact is supplied" do
      config[:hab_sup_artifact_name] = "core-hab-sup-1.6.652-20240115194501-x86_64-linux.hart"
      expect(provisioner.send(:custom_supervisor?)).to be true
    end

    it "is true when a version is pinned" do
      config[:hab_sup_version] = "1.6.652"
      expect(provisioner.send(:custom_supervisor?)).to be true
    end

    it "is true when the origin differs" do
      config[:hab_sup_origin] = "mycorp"
      expect(provisioner.send(:custom_supervisor?)).to be true
    end

    it "is true when the name differs" do
      config[:hab_sup_name] = "sup"
      expect(provisioner.send(:custom_supervisor?)).to be true
    end
  end

  describe "#install_supervisor_command" do
    it "is empty for the stock supervisor, so the script gains no blank line" do
      expect(provisioner.send(:install_supervisor_command, "  ")).to eq("")
    end

    it "installs the pinned identifier from the depot" do
      config[:hab_sup_version] = "1.6.652"
      expect(provisioner.send(:install_supervisor_command, "  "))
        .to eq("\n  hab pkg install core/hab-sup/1.6.652 --force")
    end

    it "installs a supplied artifact from where it was uploaded" do
      config[:hab_sup_artifact_name] = "core-hab-sup-1.6.652-20240115194501-x86_64-linux.hart"
      expect(provisioner.send(:install_supervisor_command, "  "))
        .to eq("\n  hab pkg install /tmp/kitchen/results/" \
               "core-hab-sup-1.6.652-20240115194501-x86_64-linux.hart --force")
    end
  end

  describe "#finalize_config!" do
    it "parses a supervisor artifact filename into its identity parts" do
      config[:hab_sup_artifact_name] = "core-hab-sup-1.6.652-20240115194501-x86_64-linux.hart"
      provisioner

      expect(config[:hab_sup_origin]).to eq("core")
      expect(config[:hab_sup_name]).to eq("hab-sup")
      expect(config[:hab_sup_version]).to eq("1.6.652")
      expect(config[:hab_sup_release]).to eq("20240115194501")
    end
  end

  describe "#supervisor_options" do
    it "passes --listen-http when configured" do
      config[:hab_sup_listen_http] = "0.0.0.0:9631"
      expect(provisioner.send(:supervisor_options)).to include("--listen-http 0.0.0.0:9631")
    end

    it "omits --listen-http when unset" do
      expect(provisioner.send(:supervisor_options)).not_to include("--listen-http")
    end
  end

  describe "#artifacts_to_upload" do
    it "is empty when no artifact is configured" do
      expect(provisioner.send(:artifacts_to_upload)).to eq([])
    end

    it "includes the service artifact" do
      config[:artifact_name] = "mycorp-app-1.0.0-20240115194501-x86_64-linux.hart"
      expect(provisioner.send(:artifacts_to_upload))
        .to eq(["mycorp-app-1.0.0-20240115194501-x86_64-linux.hart"])
    end

    it "includes a supervisor artifact on its own" do
      config[:hab_sup_artifact_name] = "core-hab-sup-1.6.652-20240115194501-x86_64-linux.hart"
      expect(provisioner.send(:artifacts_to_upload))
        .to eq(["core-hab-sup-1.6.652-20240115194501-x86_64-linux.hart"])
    end

    it "uploads both the service and the supervisor artifact" do
      config[:artifact_name] = "mycorp-app-1.0.0-20240115194501-x86_64-linux.hart"
      config[:hab_sup_artifact_name] = "core-hab-sup-1.6.652-20240115194501-x86_64-linux.hart"
      expect(provisioner.send(:artifacts_to_upload)).to contain_exactly(
        "mycorp-app-1.0.0-20240115194501-x86_64-linux.hart",
        "core-hab-sup-1.6.652-20240115194501-x86_64-linux.hart"
      )
    end
  end

  describe "generated service scripts" do
    it "installs the supervisor on Linux before starting it" do
      config[:hab_sup_version] = "1.6.652"
      script = provisioner.send(:linux_install_service)

      expect(script).to include("hab pkg install core/hab-sup/1.6.652 --force")
      expect(script.index("hab pkg install core/hab-sup/1.6.652 --force"))
        .to be < script.index("systemctl start hab-sup")
    end

    it "installs the supervisor on Windows before the Habitat service" do
      config[:hab_sup_version] = "1.6.652"
      script = provisioner.send(:windows_install_service)

      expect(script).to include("hab pkg install core/hab-sup/1.6.652 --force")
      expect(script.index("hab pkg install core/hab-sup/1.6.652 --force"))
        .to be < script.index("hab pkg install core/windows-service")
    end

    it "leaves the stock Linux script free of a blank line" do
      expect(provisioner.send(:linux_install_service)).not_to match(/hab license accept\n\s*\n/)
    end

    it "leaves the stock Windows script free of a blank line" do
      expect(provisioner.send(:windows_install_service)).not_to match(/hab license accept\n\s*\n/)
    end
  end
end
