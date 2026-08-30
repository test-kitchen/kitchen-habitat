# frozen_string_literal: true

require "kitchen/provisioner/habitat"
require "fakefs/safe"

RSpec.describe Kitchen::Provisioner::Habitat do
  include_context "habitat provisioner"

  describe "#windows_install_service" do
    it "generates a valid service install script" do
      config[:channel] = "stable"
      windows_install_service = provisioner.send(
        :windows_install_service
      )
      expected_code = <<~WINDOWS_SERVICE_SETUP
        New-Item -Path C:\\Windows\\Temp\\kitchen -ItemType Directory -Force | Out-Null
        New-Item -Path C:\\Windows\\Temp\\kitchen\\config -ItemType Directory -Force | Out-Null
        if (!($env:Path | Select-String "Habitat")) {
          $env:Path += ";C:\\ProgramData\\Habitat"
        }
        if (!(Get-Service -Name Habitat -ErrorAction Ignore)) {
          hab license accept
          Write-Output "Installing Habitat Windows Service"
          hab pkg install core/windows-service
          if ($(Get-Service -Name Habitat).Status -ne "Stopped") {
            Stop-Service -Name Habitat
          }
          $HabSvcConfig = "c:\\hab\\svc\\windows-service\\HabService.dll.config"
          [xml]$xmlDoc = Get-Content $HabSvcConfig
          $obj = $xmlDoc.configuration.appSettings.add | where {$_.Key -eq "launcherArgs" }
          $obj.value = "--no-color --channel stable"
          $xmlDoc.Save($HabSvcConfig)
          Start-Service -Name Habitat
        }
      WINDOWS_SERVICE_SETUP
      expect(windows_install_service).to eq(expected_code)
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
      expected_code = <<~LINUX_SERVICE_SETUP
        rm -rf /tmp/kitchen
        mkdir -p /tmp/kitchen/results
        mkdir -p /tmp/kitchen/config
        if [ -f /etc/systemd/system/hab-sup.service ]
        then
          echo "Hab-sup service already exists"
        else
          echo "Starting hab-sup service install"
          hab license accept
          if ! getent group hab > /dev/null 2>&1; then
            echo "Adding hab group"
            sudo -E groupadd hab
          fi
          if ! id -u hab > /dev/null 2>&1; then
            echo "Adding hab user"
            sudo -E useradd -g hab hab
          fi
          echo [Unit] | sudo tee /etc/systemd/system/hab-sup.service
          echo Description=The Chef Habitat Supervisor | sudo tee -a /etc/systemd/system/hab-sup.service
          echo [Service] | sudo tee -a /etc/systemd/system/hab-sup.service
          echo Environment="HAB_BLDR_URL=https://bldr.example.com" | sudo tee -a /etc/systemd/system/hab-sup.service
          echo Environment="HAB_LICENSE=accept" | sudo tee -a /etc/systemd/system/hab-sup.service
          echo "ExecStart=/bin/hab sup run  --channel stable" | sudo tee -a /etc/systemd/system/hab-sup.service
          echo [Install] | sudo tee -a /etc/systemd/system/hab-sup.service
          echo WantedBy=default.target | sudo tee -a /etc/systemd/system/hab-sup.service
          sudo -E systemctl daemon-reload
          sudo -E systemctl start hab-sup
          sudo -E systemctl enable hab-sup
        fi
      LINUX_SERVICE_SETUP
      expect(linux_install_service).to eq(expected_code)
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

  describe "#linux_install_service" do
    it "creates the hab group before the hab user that is placed in it" do
      script = provisioner.send(:linux_install_service)

      group_check = script.index("getent group hab")
      user_check = script.index("id -u hab")

      expect(group_check).not_to be_nil
      expect(user_check).not_to be_nil
      expect(group_check).to be < user_check
      expect(script).to include("sudo -E useradd -g hab hab")
    end

    it "omits HAB_BLDR_URL when no depot_url is configured" do
      config[:hab_license] = "accept"

      script = provisioner.send(:linux_install_service)

      expect(script).not_to include("HAB_BLDR_URL")
      expect(script).to include(%(echo Environment="HAB_LICENSE=accept" | sudo tee -a /etc/systemd/system/hab-sup.service))
    end

    it "omits HAB_LICENSE when no hab_license is configured" do
      config[:depot_url] = "https://bldr.example.com"

      script = provisioner.send(:linux_install_service)

      expect(script).not_to include("HAB_LICENSE")
      expect(script).to include(%(echo Environment="HAB_BLDR_URL=https://bldr.example.com" | sudo tee -a /etc/systemd/system/hab-sup.service))
    end

    it "writes no Environment lines at all when neither is configured" do
      script = provisioner.send(:linux_install_service)

      expect(script).not_to include("Environment=")
      expect(script).to include("echo [Service] | sudo tee -a /etc/systemd/system/hab-sup.service\n")
    end

    it "leaves no blank line behind when the Environment lines are omitted" do
      expect(provisioner.send(:linux_install_service)).not_to match(/\n[ \t]*\n/)
    end
  end
end
