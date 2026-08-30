# frozen_string_literal: true

require "kitchen/provisioner/habitat"
require "fakefs/safe"

RSpec.describe Kitchen::Provisioner::Habitat do
  include_context "habitat provisioner"

  describe "#resolve_results_directory" do
    it "returns the results_directory when specified in config" do
      config[:results_directory] = "/kitchen/results"
      resolve_results_directory = provisioner.send(
        :resolve_results_directory
      )
      expect(resolve_results_directory).to eq("/kitchen/results")
    end
    it "returns the current path if it includes the results folder" do
      results_dir = "/kroot/results"
      FakeFS.activate!
      FileUtils.mkdir_p(results_dir)

      resolve_results_directory = provisioner.send(
        :resolve_results_directory
      )
      expect(resolve_results_directory).to eq(results_dir)
      FakeFS.deactivate!
      FakeFS::FileSystem.clear
    end
  end

  describe "#full_user_toml_path" do
    describe "for windows operating systems" do
      before { allow(platform).to receive(:os_type).and_return("windows") }
      it "should return the local path to the user.toml" do
        config[:kitchen_root] = "c:/kitchen"
        config[:config_directory] = "config"
        config[:user_toml_name] = "user.toml"
        full_user_toml_path = provisioner.send(
          :full_user_toml_path
        )
        expect(full_user_toml_path).to eq("c:/kitchen/config/user.toml")
      end
    end

    describe "for unix operating systems" do
      before { allow(platform).to receive(:os_type).and_return("linux") }
      it "should return the local path to the user.toml" do
        config[:config_directory] = "config"
        config[:user_toml_name] = "user.toml"
        full_user_toml_path = provisioner.send(
          :full_user_toml_path
        )
        expect(full_user_toml_path).to eq("/kroot/config/user.toml")
      end
    end
  end

  describe "#sandbox_user_toml_path" do
    it "should return the sandbox path to the user.toml" do
      provisioner.create_sandbox
      config[:config_directory] = "configs"
      config[:user_toml_name] = "user.toml"
      sandbox_user_toml_path = provisioner.send(
        :sandbox_user_toml_path
      )
      expect(sandbox_user_toml_path).to eq("#{provisioner.sandbox_path}/config/user.toml")
      provisioner.cleanup_sandbox
    end
  end

  describe "#copy_user_toml_to_service_directory" do
    describe "for windows operating systems" do
      before { allow(platform).to receive(:os_type).and_return("windows") }

      it "should copy the toml to svc dir on windows" do
        config[:kitchen_root] = "c:/kitchen"
        config[:package_name] = "package"
        config[:config_directory] = "config"
        config[:user_toml_name] = "user.toml"

        FakeFS.activate!
        FileUtils.mkdir_p("c:/kitchen/config")
        FileUtils.touch("c:/kitchen/config/user.toml")

        copy_user_toml_to_service_directory = provisioner.send(
          :copy_user_toml_to_service_directory
        )
        expected_code = <<~PWSH
          New-Item -Path c:\\hab\\user\\package\\config -ItemType Directory -Force  | Out-Null
          Copy-Item -Path $env:TEMP\\kitchen/config/user.toml -Destination c:\\hab\\user\\package\\config\\user.toml -Force
        PWSH
        expect(copy_user_toml_to_service_directory).to eq(expected_code)
        FakeFS.deactivate!
        FakeFS::FileSystem.clear
      end
    end

    describe "for unix operating systems" do
      before { allow(platform).to receive(:os_type).and_return("linux") }

      it "should copy the toml to svc dir on linux" do
        config[:package_name] = "package"
        config[:config_directory] = "config"
        config[:user_toml_name] = "user.toml"

        FakeFS.activate!
        FileUtils.mkdir_p("/kroot/config/")
        FileUtils.touch("/kroot/config/user.toml")

        copy_user_toml_to_service_directory = provisioner.send(
          :copy_user_toml_to_service_directory
        )
        expected_code = <<~BASH
          sudo -E mkdir -p /hab/user/package/config
          sudo -E cp /tmp/kitchen/config/user.toml /hab/user/package/config/user.toml
        BASH
        expect(copy_user_toml_to_service_directory).to eq(expected_code)
        FakeFS.deactivate!
        FakeFS::FileSystem.clear
      end
    end
  end

  describe "#remove_previous_user_toml" do
    describe "for windows operating systems" do
      before { allow(platform).to receive(:os_type).and_return("windows") }

      it "should remove the toml on windows" do
        config[:package_name] = "package"
        remove_previous_user_toml = provisioner.send(
          :remove_previous_user_toml
        )
        expected_code = <<~PWSH
          if (Test-Path c:\\hab\\user\\package\\config\\user.toml) {
            Remove-Item -Path c:\\hab\\user\\package\\config\\user.toml -Force
          }
        PWSH
        expect(remove_previous_user_toml).to eq(expected_code)
      end
    end

    describe "for unix operating systems" do
      before { allow(platform).to receive(:os_type).and_return("linux") }

      it "should remove the toml on linux" do
        config[:package_name] = "package"
        remove_previous_user_toml = provisioner.send(
          :remove_previous_user_toml
        )
        expected_code = <<~BASH
          if [ -d "/hab/user/package/config" ]; then
            sudo -E find /hab/user/package/config -name user.toml -delete
          fi
        BASH
        expect(remove_previous_user_toml).to eq(expected_code)
      end
    end
  end
end
