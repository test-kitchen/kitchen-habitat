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
  left_padded_code = code.map do |line|
    line.rjust(line.length + left_pad_length)
  end.join("\n")
  command = "#{left_padded_code}\n"
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

  describe "#windows_install_cmd" do
    it "generates a valid install script" do
      config[:hab_channel] = "stable"
      config[:hab_version] = "1.5.29"
      windows_install_cmd = provisioner.send(
        :windows_install_cmd
      )
      expected_code = [
        "if ((Get-Command hab -ErrorAction Ignore).Path) {",
        "  Write-Output \"Habitat CLI already installed.\"",
        "} else {",
        "  Set-ExecutionPolicy Bypass -Scope Process -Force",
        "  $InstallScript = ((New-Object System.Net.WebClient).DownloadString('https://raw.githubusercontent.com/habitat-sh/habitat/master/components/hab/install.ps1'))",
        "  Invoke-Command -ScriptBlock ([scriptblock]::Create($InstallScript)) -ArgumentList stable, 1.5.29",
        "}",
      ]
      expect(windows_install_cmd).to eq(wrap_command(expected_code, 0))
    end
  end

  describe "#linux_install_cmd" do
    it "generates a valid install script" do
      config[:hab_version] = "1.5.29"
      linux_install_cmd = provisioner.send(
        :linux_install_cmd
      )
      expected_code = [
        "if command -v hab >/dev/null 2>&1",
        "then",
        "  echo \"Habitat CLI already installed.\"",
        "else",
        "  curl -o /tmp/install.sh 'https://raw.githubusercontent.com/habitat-sh/habitat/master/components/hab/install.sh'",
        "  sudo -E bash /tmp/install.sh -v 1.5.29",
        "fi",
      ]
      expect(linux_install_cmd).to eq(wrap_command(expected_code, 0))
    end
  end

  describe "#windows_install_service" do
    it "generates a valid service install script" do
      config[:channel] = "stable"
      windows_install_service = provisioner.send(
        :windows_install_service
      )
      expected_code = [
        "New-Item -Path C:\\Windows\\Temp\\kitchen -ItemType Directory -Force | Out-Null",
        "New-Item -Path C:\\Windows\\Temp\\kitchen\\config -ItemType Directory -Force | Out-Null",
        "if (!($env:Path | Select-String \"Habitat\")) {",
        "  $env:Path += \";C:\\ProgramData\\Habitat\"",
        "}",
        "if (!(Get-Service -Name Habitat -ErrorAction Ignore)) {",
        "  hab license accept",
        "  Write-Output \"Installing Habitat Windows Service\"",
        "  hab pkg install core/windows-service",
        "  if ($(Get-Service -Name Habitat).Status -ne \"Stopped\") {",
        "    Stop-Service -Name Habitat",
        "  }",
        "  $HabSvcConfig = \"c:\\hab\\svc\\windows-service\\HabService.dll.config\"",
        "  [xml]$xmlDoc = Get-Content $HabSvcConfig",
        "  $obj = $xmlDoc.configuration.appSettings.add | where {$_.Key -eq \"launcherArgs\" }",
        "  $obj.value = \"--no-color --channel stable\"",
        "  $xmlDoc.Save($HabSvcConfig)",
        "  Start-Service -Name Habitat",
        "}",
      ]
      expect(windows_install_service).to eq(wrap_command(expected_code, 0))
    end
  end

  describe "#linux_install_service" do
    it "generates a valid service install script" do
      config[:channel] = "stable"
      config[:depot_url] = "https://bldr.example.com"
      config[:hab_license] = "accept"
      linux_install_service = provisioner.send(
        :linux_install_service
      )
      expected_code = [
        "id -u hab >/dev/null 2>&1 || sudo -E useradd hab >/dev/null 2>&1",
        "rm -rf /tmp/kitchen",
        "mkdir -p /tmp/kitchen/results",
        "mkdir -p /tmp/kitchen/config",
        "if [ -f /etc/systemd/system/hab-sup.service ]",
        "then",
        "  echo \"Hab-sup service already exists\"",
        "else",
        "  echo \"Starting hab-sup service install\"",
        "  hab license accept",
        "  if ! id -u hab > /dev/null 2>&1; then",
        "    echo \"Adding hab user\"",
        "    sudo -E groupadd hab",
        "  fi",
        "  if ! id -g hab > /dev/null 2>&1; then",
        "    echo \"Adding hab group\"",
        "    sudo -E useradd -g hab hab",
        "  fi",
        "  echo [Unit] | sudo tee /etc/systemd/system/hab-sup.service",
        "  echo Description=The Chef Habitat Supervisor | sudo tee -a /etc/systemd/system/hab-sup.service",
        "  echo [Service] | sudo tee -a /etc/systemd/system/hab-sup.service",
        "  echo Environment=\"HAB_BLDR_URL=https://bldr.example.com\" | sudo tee -a /etc/systemd/system/hab-sup.service",
        "  echo Environment=\"HAB_LICENSE=accept\" | sudo tee -a /etc/systemd/system/hab-sup.service",
        "  echo \"ExecStart=/bin/hab sup run  --channel stable\" | sudo tee -a /etc/systemd/system/hab-sup.service",
        "  echo [Install] | sudo tee -a /etc/systemd/system/hab-sup.service",
        "  echo WantedBy=default.target | sudo tee -a /etc/systemd/system/hab-sup.service",
        "  sudo -E systemctl daemon-reload",
        "  sudo -E systemctl start hab-sup",
        "  sudo -E systemctl enable hab-sup",
        "fi",
      ]
      expect(linux_install_service).to eq(wrap_command(expected_code, 0))
    end
  end

  describe "#resolve_results_directory" do
    # let(:directory) { 'dir.d' }
    # before(:each) { create_directory(directory) }

    # it { expect(directory).to be_an_existing_directory }
    xit "returns the current path if it includes the results folder" do
    #   #config[:kitchen_root] = "/tmp/kitchen"
    #   resolve_results_directory = provisioner.send(
    #     :resolve_results_directory
    #   )
    #   expect(linux_install_service).to eq("/tmp/kitchen/results")
    end
    xit "returns the parent path if it includes the results folder" do
      #   #config[:kitchen_root] = "/tmp/kitchen"
      #   resolve_results_directory = provisioner.send(
      #     :resolve_results_directory
      #   )
      #   expect(linux_install_service).to eq("/tmp/kitchen/results")
    end
    xit "returns the grandparent path if it includes the results folder" do
      #   #config[:kitchen_root] = "/tmp/kitchen"
      #   resolve_results_directory = provisioner.send(
      #     :resolve_results_directory
      #   )
      #   expect(linux_install_service).to eq("/tmp/kitchen/results")
    end
  end

  describe "#copy_package_config_from_override_to_sandbox" do
    xit "should create a config folder in the sandbox" do
    end
  end

  describe "#copy_results_to_sandbox" do
    xit "should create a results folder in the sandbox" do
    end
  end

  describe "#full_user_toml_path" do
    it "should return the local path to the user.toml" do
      config[:config_directory] = "configs"
      config[:user_toml_name] = "user.toml"
      full_user_toml_path = provisioner.send(
        :full_user_toml_path
      )
      expect(full_user_toml_path).to eq("/kroot/configs/user.toml")
    end
  end

  describe "#sandbox_user_toml_path" do
    xit "should return the sandbox path to the user.toml" do
      config[:config_directory] = "configs"
      config[:user_toml_name] = "user.toml"
      sandbox_user_toml_path = provisioner.send(
        :sandbox_user_toml_path
      )
      expect(sandbox_user_toml_path).to eq("/tmp/kitchen/configs/user.toml")
    end
  end

  describe "#copy_user_toml_to_sandbox" do
    xit "copy the user.toml to the sandbox" do
    end
  end

  describe "#latest_artifact_name" do
    xit "return the name of the most recent artifact" do
    end
  end

  describe "#copy_user_toml_to_service_directory" do
    describe "for windows operating systems" do
      before { platform.stubs(:os_type).returns("windows") }

      xit "should copy the toml to svc dir on windows" do
        copy_user_toml_to_service_directory = provisioner.send(
          :copy_user_toml_to_service_directory
        )
        expected_code = [
          "New-Item -Path c:\\hab\\user\\package\\config -ItemType Directory -Force  | Out-Null",
          "Copy-Item -Path #{File.join(File.join(config[:root_path], "config"), "user.toml")} -Destination c:\\hab\\user\\package\\config\\user.toml -Force",
        ]
        expect(copy_user_toml_to_service_directory).to eq(wrap_command(expected_code, 0))
      end
    end

    describe "for unix operating systems" do
      before { platform.stubs(:os_type).returns("linux") }

      xit "should copy the toml to svc dir on linux" do
        copy_user_toml_to_service_directory = provisioner.send(
          :copy_user_toml_to_service_directory
        )
        expected_code = [
          "sudo -E mkdir -p /hab/user/package/config",
          "sudo -E cp #{File.join(File.join(config[:root_path], "config"), "user.toml")} /hab/user/package/config/user.toml",
        ]
        expect(copy_user_toml_to_service_directory).to eq(wrap_command(expected_code, 0))
      end
    end
  end

  describe "#remove_previous_user_toml" do
    describe "for windows operating systems" do
      before { platform.stubs(:os_type).returns("windows") }

      xit "should remove the toml on windows" do
        config[:package_name] = "package"
        remove_previous_user_toml = provisioner.send(
          :remove_previous_user_toml
        )
        expected_code = [
          "if (Test-Path c:\\hab\\user\\package\\config\\user.toml) {",
          "  Remove-Item -Path c:\\hab\\user\\package\\config\\user.toml -Force",
          "}",
        ]
        expect(remove_previous_user_toml).to eq(wrap_command(expected_code, 0))
      end
    end

    describe "for unix operating systems" do
      before { platform.stubs(:os_type).returns("linux") }

      xit "should remove the toml on linux" do
        config[:package_name] = "package"
        remove_previous_user_toml = provisioner.send(
          :remove_previous_user_toml
        )
        expected_code = [
          "if [ -d \"/hab/user/package/config\" ]; then",
          "  sudo -E find /hab/user/package/config -name user.toml -delete",
          "fi",
        ]
        expect(remove_previous_user_toml).to eq(wrap_command(expected_code, 0))
      end
    end
  end

  describe "#artifact_name_to_package_ident_regex" do
    xit "produce the package ident (origin/name/version/release from the artifact filename" do
      config[:artifact_name] = "example-package-0.1.0-20200406205105-x86_64-linux.hart"
      artifact_name_to_package_ident_regex = provisioner.send(
        :artifact_name_to_package_ident_regex
      )
      expect(artifact_name_to_package_ident_regex.match(config[:artifact_name])).to include("origin:\"example\"")
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
    it "should resolve the target artifact name" do
      config[:artifact_name] = "example-package-0.1.0-20200406205105-x86_64-linux.hart"
      get_artifact_name = provisioner.send(
        :get_artifact_name
      )
      expect(get_artifact_name).to eq("/tmp/kitchen/results/example-package-0.1.0-20200406205105-x86_64-linux.hart")
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

    it "sets the --listen_gossip flag when config[:hab_sup_listen_gossip] is set" do
      config[:hab_sup_listen_gossip] = "0.0.0.0:9638"
      supervisor_options = provisioner.send(
        :supervisor_options
      )
      expect(supervisor_options).to include("--listen-gossip 0.0.0.0:9638")
    end

    it "doesn't set the --listen_gossip flag when config[:hab_sup_listen_gossip] is unset" do
      supervisor_options = provisioner.send(
        :supervisor_options
      )
      expect(supervisor_options).not_to include("--listen-gossip 0.0.0.0:9638")
    end

    it "sets the --config-from flag when config[:override_package_config] is set" do
      config[:override_package_config] = "true"
      supervisor_options = provisioner.send(
        :supervisor_options
      )
      expect(supervisor_options).to include("--config-from /tmp/kitchen/config/")
    end

    it "doesn't set the --config-from flag when config[:hab_sup_ring] is unset" do
      supervisor_options = provisioner.send(
        :supervisor_options
      )
      expect(supervisor_options).not_to include("--config-from /tmp/kitchen/config/")
    end

    it "sets the --bind flag when config[:hab_sup_bind] is set with a single binding" do
      config[:hab_sup_bind] = ["database:database.default"]
      supervisor_options = provisioner.send(
        :supervisor_options
      )
      expect(supervisor_options).to include("--bind database:database.default")
    end

    it "sets the --bind flag when config[:hab_sup_bind] is set with multiple bindings" do
      config[:hab_sup_bind] = ["web:web.default", "database:database.default"]
      supervisor_options = provisioner.send(
        :supervisor_options
      )
      expect(supervisor_options).to include("--bind web:web.default  --bind database:database.default")
    end

    it "doesn't set the --bind flag when config[:hab_sup_bind] is unset" do
      supervisor_options = provisioner.send(
        :supervisor_options
      )
      expect(supervisor_options).not_to include("--bind test")
    end

    it "sets the --peer flag when config[:hab_sup_peer] is set with a single peer" do
      config[:hab_sup_peer] = ["1.1.1.1"]
      supervisor_options = provisioner.send(
        :supervisor_options
      )
      expect(supervisor_options).to include("--peer 1.1.1.1")
    end

    it "sets the --peer flag when config[:hab_sup_peer] is set with multiple peers" do
      config[:hab_sup_peer] = ["1.1.1.1", "2.2.2.2"]
      supervisor_options = provisioner.send(
        :supervisor_options
      )
      expect(supervisor_options).to include("--peer 1.1.1.1  --peer 2.2.2.2")
    end

    it "doesn't set the --peer flag when config[:hab_sup_peer] is unset" do
      supervisor_options = provisioner.send(
        :supervisor_options
      )
      expect(supervisor_options).not_to include("--peer 1.1.1.1")
    end

    it "sets the --group flag when config[:hab_sup_group] is set" do
      config[:hab_sup_group] = "default"
      supervisor_options = provisioner.send(
        :supervisor_options
      )
      expect(supervisor_options).to include("--group default")
    end

    it "doesn't set the --group flag when config[:hab_sup_group] is unset" do
      supervisor_options = provisioner.send(
        :supervisor_options
      )
      expect(supervisor_options).not_to include("--group default")
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

    it "sets the --topology flag when config[:service_topology] is set" do
      config[:service_topology] = "standalone"
      supervisor_options = provisioner.send(
        :supervisor_options
      )
      expect(supervisor_options).to include("--topology standalone")
    end

    it "doesn't set the --topology flag when config[:service_topology] is unset" do
      supervisor_options = provisioner.send(
        :supervisor_options
      )
      expect(supervisor_options).not_to include("--topology standalone")
    end

    it "sets the --strategy flag when config[:service_update_strategy] is set" do
      config[:service_update_strategy] = "at-once"
      supervisor_options = provisioner.send(
        :supervisor_options
      )
      expect(supervisor_options).to include("--strategy at-once")
    end

    it "doesn't set the --strategy flag when config[:service_update_strategy] is unset" do
      supervisor_options = provisioner.send(
        :supervisor_options
      )
      expect(supervisor_options).not_to include("--strategy at-once")
    end

    it "sets the --channel flag when config[:channel] is set" do
      config[:channel] = "staging"
      supervisor_options = provisioner.send(
        :supervisor_options
      )
      expect(supervisor_options).to include("--channel staging")
    end

    it "doesn't set the --channel flag when config[:channel] is unset" do
      supervisor_options = provisioner.send(
        :supervisor_options
      )
      expect(supervisor_options).not_to include("--channel staging")
    end

    it "sets the --event-stream-application flag when config[:event_stream_application] is set" do
      config[:event_stream_application] = "test"
      supervisor_options = provisioner.send(
        :supervisor_options
      )
      expect(supervisor_options).to include("--event-stream-application test")
    end

    it "doesn't set the --event-stream-application flag when config[:event_stream_application] is unset" do
      supervisor_options = provisioner.send(
        :supervisor_options
      )
      expect(supervisor_options).not_to include("--event-stream-application test")
    end

    it "sets the --event-stream-environment flag when config[:event_stream_environment] is set" do
      config[:event_stream_environment] = "test"
      supervisor_options = provisioner.send(
        :supervisor_options
      )
      expect(supervisor_options).to include("--event-stream-environment test")
    end

    it "doesn't set the --event-stream-environment flag when config[:hab_sup_ring] is unset" do
      supervisor_options = provisioner.send(
        :supervisor_options
      )
      expect(supervisor_options).not_to include("--event-stream-environment test")
    end

    it "sets the --event-stream-site flag when config[:event_stream_site] is set" do
      config[:event_stream_site] = "test"
      supervisor_options = provisioner.send(
        :supervisor_options
      )
      expect(supervisor_options).to include("--event-stream-site test")
    end

    it "doesn't set the --event-stream-site flag when config[:event_stream_site] is unset" do
      supervisor_options = provisioner.send(
        :supervisor_options
      )
      expect(supervisor_options).not_to include("--event-stream-site test")
    end

    it "sets the --event-stream-url flag when config[:event_stream_url] is set" do
      config[:event_stream_url] = "test"
      supervisor_options = provisioner.send(
        :supervisor_options
      )
      expect(supervisor_options).to include("--event-stream-url test")
    end

    it "doesn't set the --event-stream-url flag when config[:event_stream_url] is unset" do
      supervisor_options = provisioner.send(
        :supervisor_options
      )
      expect(supervisor_options).not_to include("--event-stream-url test")
    end

    it "sets the --event-stream-token flag when config[:event_stream_token] is set" do
      config[:event_stream_token] = "test"
      supervisor_options = provisioner.send(
        :supervisor_options
      )
      expect(supervisor_options).to include("--event-stream-token test")
    end

    it "doesn't set the --event-stream-token flag when config[:event_stream_token] is unset" do
      supervisor_options = provisioner.send(
        :supervisor_options
      )
      expect(supervisor_options).not_to include("--event-stream-token test")
    end
  end

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
end
