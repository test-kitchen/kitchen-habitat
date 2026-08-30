# frozen_string_literal: true

require "kitchen/provisioner/habitat"
require "tmpdir" unless defined?(Dir.mktmpdir)

# These examples use a real temporary directory rather than FakeFS. The
# sandbox that Kitchen::Provisioner::Base creates lives on the real
# filesystem, so a faked kitchen_root leaves the copy helpers with nothing to
# copy and they silently return -- which looks like a passing spec while
# testing nothing.
RSpec.describe Kitchen::Provisioner::Habitat do
  include_context "habitat provisioner"

  let(:kitchen_root) { Dir.mktmpdir("kitchen-habitat-spec") }
  let(:config) { { kitchen_root: kitchen_root, root_path: "/tmp/kitchen" } }

  after do
    provisioner.cleanup_sandbox if provisioner.instance_variable_get(:@sandbox_path)
    FileUtils.remove_entry(kitchen_root) if File.directory?(kitchen_root)
  end

  def write(relative_path, contents = "")
    path = File.join(kitchen_root, relative_path)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, contents)
    path
  end

  def sandbox_entries
    Dir.glob(File.join(provisioner.sandbox_path, "**", "*"))
      .map { |p| p.sub("#{provisioner.sandbox_path}/", "") }
      .sort
  end

  describe "#resolve_results_directory" do
    it "prefers an explicitly configured directory over any it could find" do
      write("results/keep.txt")
      config[:results_directory] = "/somewhere/else"

      expect(provisioner.send(:resolve_results_directory)).to eq("/somewhere/else")
    end

    it "finds results/ beside the kitchen.yml" do
      write("results/keep.txt")

      expect(provisioner.send(:resolve_results_directory)).to eq(File.join(kitchen_root, "results"))
    end

    it "falls back to the parent directory, as hab studio lays a plan out" do
      nested = File.join(kitchen_root, "habitat", "test")
      FileUtils.mkdir_p(nested)
      write("habitat/results/keep.txt")
      config[:kitchen_root] = nested

      expect(provisioner.send(:resolve_results_directory)).to eq(File.join(nested, "../results"))
    end

    it "falls back to the grandparent directory" do
      nested = File.join(kitchen_root, "habitat", "test")
      FileUtils.mkdir_p(nested)
      write("results/keep.txt")
      config[:kitchen_root] = nested

      expect(provisioner.send(:resolve_results_directory)).to eq(File.join(nested, "../../results"))
    end

    it "returns nil when there is no results directory anywhere it looks" do
      expect(provisioner.send(:resolve_results_directory)).to be_nil
    end
  end

  describe "#copy_results_to_sandbox" do
    let(:artifact) { "mycorp-wildfly-26.1.1-20240115194501-x86_64-linux.hart" }

    it "copies the named artifact into the sandbox" do
      write("results/#{artifact}", "HART")
      config[:artifact_name] = artifact

      provisioner.create_sandbox

      expect(sandbox_entries).to include("results", "results/#{artifact}")
      expect(File.read(File.join(provisioner.sandbox_path, "results", artifact))).to eq("HART")
    end

    it "copies the newest matching artifact when install_latest_artifact is set" do
      write("results/mycorp-wildfly-26.1.0-20240101000000-x86_64-linux.hart", "OLD")
      newest = write("results/mycorp-wildfly-26.1.1-20240115194501-x86_64-linux.hart", "NEW")
      FileUtils.touch(newest, mtime: Time.now + 60)
      config[:install_latest_artifact] = true
      config[:package_origin] = "mycorp"
      config[:package_name] = "wildfly"

      provisioner.create_sandbox

      expect(sandbox_entries).to include("results/mycorp-wildfly-26.1.1-20240115194501-x86_64-linux.hart")
      expect(sandbox_entries).not_to include("results/mycorp-wildfly-26.1.0-20240101000000-x86_64-linux.hart")
    end

    it "copies a custom supervisor artifact alongside the service artifact" do
      write("results/#{artifact}", "HART")
      write("results/core-hab-sup-1.6.652-20240115194501-x86_64-linux.hart", "SUP")
      config[:artifact_name] = artifact
      config[:hab_sup_artifact_name] = "core-hab-sup-1.6.652-20240115194501-x86_64-linux.hart"

      provisioner.create_sandbox

      expect(sandbox_entries).to include(
        "results/#{artifact}",
        "results/core-hab-sup-1.6.652-20240115194501-x86_64-linux.hart"
      )
    end

    it "creates no results directory when no artifact was asked for" do
      write("results/#{artifact}", "HART")

      provisioner.create_sandbox

      expect(sandbox_entries).not_to include("results")
    end
  end

  describe "#copy_user_toml_to_sandbox" do
    it "copies the user.toml out of config_directory" do
      write("configs/user.toml", "[redis]\nport = 6380\n")
      config[:config_directory] = "configs"

      provisioner.create_sandbox

      expect(File.read(File.join(provisioner.sandbox_path, "config", "user.toml")))
        .to eq("[redis]\nport = 6380\n")
    end

    it "renames the file named by user_toml_name to user.toml in the sandbox" do
      write("configs/user-ha.toml", "ha = true\n")
      config[:config_directory] = "configs"
      config[:user_toml_name] = "user-ha.toml"

      provisioner.create_sandbox

      expect(sandbox_entries).to include("config/user.toml")
      expect(sandbox_entries).not_to include("config/user-ha.toml")
    end

    it "does nothing when config_directory holds no such file" do
      write("configs/default.toml", "")
      config[:config_directory] = "configs"

      provisioner.create_sandbox

      expect(sandbox_entries).not_to include("config/user.toml")
    end

    it "does nothing when no config_directory is set" do
      provisioner.create_sandbox

      expect(sandbox_entries).to be_empty
    end
  end

  describe "#copy_package_config_from_override_to_sandbox" do
    before do
      write("configs/user.toml", "port = 6380\n")
      write("configs/default.toml", "port = 6379\n")
      write("configs/hooks/run", "#!/bin/sh\n")
    end

    it "copies the whole config directory when override_package_config is set" do
      config[:config_directory] = "configs"
      config[:override_package_config] = true

      provisioner.create_sandbox

      expect(sandbox_entries).to include("config/default.toml", "config/hooks/run", "config/user.toml")
    end

    it "copies only the user.toml when override_package_config is not set" do
      config[:config_directory] = "configs"

      provisioner.create_sandbox

      expect(sandbox_entries).to contain_exactly("config", "config/user.toml")
    end

    it "does nothing when the configured directory does not exist" do
      config[:config_directory] = "nope"
      config[:override_package_config] = true

      provisioner.create_sandbox

      expect(sandbox_entries).to be_empty
    end
  end

  describe "#get_artifact_name" do
    it "resolves the newest artifact and back-fills the package identity" do
      write("results/mycorp-wildfly-26.1.0-20240101000000-x86_64-linux.hart", "OLD")
      newest = write("results/mycorp-wildfly-26.1.1-20240115194501-x86_64-linux.hart", "NEW")
      FileUtils.touch(newest, mtime: Time.now + 60)
      config[:install_latest_artifact] = true
      config[:package_origin] = "mycorp"
      config[:package_name] = "wildfly"

      path = provisioner.send(:get_artifact_name)

      expect(path).to eq("/tmp/kitchen/results/mycorp-wildfly-26.1.1-20240115194501-x86_64-linux.hart")
      expect(provisioner.send(:config)[:package_version]).to eq("26.1.1")
      expect(provisioner.send(:config)[:package_release]).to eq("20240115194501")
    end

    it "returns nil when no local artifact was asked for" do
      expect(provisioner.send(:get_artifact_name)).to be_nil
    end
  end
end
