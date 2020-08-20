#
# Author:: Steven Murawski (<steven.murawski@gmail.com>)
#
# Copyright (C) 2017 Steven Murawski
#
# Licensed under the MIT License.
# See LICENSE for more details

require "fileutils" unless defined?(FileUtils)
require "pathname" unless defined?(Pathname)
require "kitchen/provisioner/base"
require "kitchen/util"

module Kitchen
  module Provisioner
    class Habitat < Base
      kitchen_provisioner_api_version 2

      default_config :depot_url, nil
      default_config :hab_license, nil
      default_config :hab_version, "latest"
      default_config :hab_channel, "stable"
      default_config :hab_sup_origin, "core"
      default_config :hab_sup_name, "hab-sup"
      default_config :hab_sup_version, nil
      default_config :hab_sup_release, nil
      default_config :hab_sup_artifact_name, nil

      # hab-sup manager options
      default_config :hab_sup_listen_http, nil
      default_config :hab_sup_listen_gossip, nil
      default_config :hab_sup_listen_ctl, nil
      default_config :hab_sup_peer, []
      default_config :hab_sup_bind, []
      default_config :hab_sup_group, nil
      default_config :hab_sup_ring, nil

      # hab-sup service options
      default_config :install_latest_artifact, false
      default_config :artifact_name, nil
      default_config :package_origin, "core"
      default_config :package_name
      default_config :package_version, nil
      default_config :package_release, nil
      default_config :service_topology, nil
      default_config :service_update_strategy, nil
      default_config :channel, "stable"
      default_config :service_load_timeout, 300

      # local stuffs to copy
      default_config :results_directory, nil
      default_config :config_directory, nil
      default_config :user_toml_name, "user.toml"
      default_config :override_package_config, false

      # event stream options
      default_config :event_stream_application, nil
      default_config :event_stream_environment, nil
      default_config :event_stream_site, nil
      default_config :event_stream_url, nil
      default_config :event_stream_token, nil

      def finalize_config!(instance)
        # Check to see if a package ident was specified for package name and be helpful
        unless config[:package_name].nil? || (config[:package_name] =~ %r{/}).nil?
          config[:package_origin], config[:package_name], config[:package_version], config[:package_release] = config[:package_name].split("/")
        end

        unless config[:hab_sup_artifact_name].nil?
          ident = artifact_name_to_package_ident_regex.match(config[:hab_sup_artifact_name])
          config[:hab_sup_origin] = ident["origin"]
          config[:hab_sup_name] = ident["name"]
          config[:hab_sup_version] = ident["version"]
          config[:hab_sup_release] = ident["release"]
        end

        unless config[:artifact_name].nil?
          ident = artifact_name_to_package_ident_regex.match(config[:artifact_name])
          config[:package_origin] = ident["origin"]
          config[:package_name] = ident["name"]
          config[:package_version] = ident["version"]
          config[:package_release] = ident["release"]
        end
        super(instance)
      end

      def install_command
        if windows_os?
          wrap_shell_code(windows_install_cmd)
        else
          wrap_shell_code(linux_install_cmd)
        end
      end

      def init_command
        if windows_os?
          wrap_shell_code(windows_install_service)
        else
          wrap_shell_code(linux_install_service)
        end
      end

      def create_sandbox
        super
        copy_results_to_sandbox
        copy_user_toml_to_sandbox
        copy_package_config_from_override_to_sandbox
      end

      def prepare_command
        debug("Prepare command is running")
        wrap_shell_code <<~PREPARE
          #{remove_previous_user_toml}
          #{copy_user_toml_to_service_directory}
        PREPARE
      end

      def run_command
        # This little bit figures out what package should be loaded
        if config[:install_latest_artifact] || !config[:artifact_name].nil?
          # TODO: throw error and bail if there's no artifacts in the results directory
          target_pkg = get_artifact_name
          target_ident = "#{config[:package_origin]}/#{config[:package_name]}"
          # TODO: This is a workaround for windows. The hart file sometimes gets copied to the
          # %TEMP%\kitchen instead of %TEMP%\kitchen\results.
          if windows_os?
            target_pkg = target_pkg.gsub("results/", "") unless File.exist?(target_pkg)
          end
        else
          target_pkg = package_ident
          target_ident = package_ident
        end

        if windows_os?
          wrap_shell_code <<~PWSH
            if (!($env:Path | Select-String "Habitat")) {
              $env:Path += ";C:\\ProgramData\\Habitat"
            }
            hab pkg install #{target_pkg} --channel #{config[:channel]} --force
            if (Test-Path -Path "$(hab pkg path #{target_ident})\\hooks\\run") {
              hab svc load #{target_ident} #{service_options} --force
              $timer = 0
              Do {
                if ($timer -gt #{config[:service_load_timeout]}){exit 1}
                Start-Sleep -Seconds 1
                $timer++
              } until( hab svc status | out-string -stream | select-string #{target_ident})
            }
          PWSH
        else
          wrap_shell_code <<~BASH
            until sudo -E hab svc status > /dev/null
              do
                echo "Waiting 5 seconds for supervisor to finish loading"
                sleep 5
              done
            sudo hab pkg install #{target_pkg} --channel #{config[:channel]} --force
            if [ -f $(sudo hab pkg path #{target_ident})/hooks/run ]
              then
                sudo -E hab svc load #{target_ident} #{service_options} --force
                timer=0
                until sudo -E hab svc status | grep #{target_ident}
                  do
                    if [$timer -gt #{config[:service_load_timeout]}]; then exit 1; fi
                    sleep 1
                    $timer++
                  done
            fi
          BASH
        end
      end

      private

      def windows_install_cmd
        <<~PWSH
          if ((Get-Command hab -ErrorAction Ignore).Path) {
            Write-Output "Habitat CLI already installed."
          } else {
            Set-ExecutionPolicy Bypass -Scope Process -Force
            $InstallScript = ((New-Object System.Net.WebClient).DownloadString('https://raw.githubusercontent.com/habitat-sh/habitat/master/components/hab/install.ps1'))
            Invoke-Command -ScriptBlock ([scriptblock]::Create($InstallScript)) -ArgumentList #{config[:hab_channel]}, #{config[:hab_version]}
          }
        PWSH
      end

      def linux_install_cmd
        version = " -v #{config[:hab_version]}" unless config[:hab_version].eql?("latest")
        <<~BASH
          if command -v hab >/dev/null 2>&1
          then
            echo "Habitat CLI already installed."
          else
            curl -o /tmp/install.sh 'https://raw.githubusercontent.com/habitat-sh/habitat/master/components/hab/install.sh'
            sudo -E bash /tmp/install.sh#{version}
          fi
        BASH
      end

      def windows_install_service
        <<~WINDOWS_SERVICE_SETUP
          New-Item -Path C:\\Windows\\Temp\\kitchen -ItemType Directory -Force | Out-Null
          #{"New-Item -Path C:\\Windows\\Temp\\kitchen\\config -ItemType Directory -Force | Out-Null" unless config[:override_package_config]}
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
            $obj.value = "--no-color#{supervisor_options}"
            $xmlDoc.Save($HabSvcConfig)
            Start-Service -Name Habitat
          }
        WINDOWS_SERVICE_SETUP
      end

      def linux_install_service
        <<~LINUX_SERVICE_SETUP
          id -u hab >/dev/null 2>&1 || sudo -E useradd hab >/dev/null 2>&1
          rm -rf /tmp/kitchen
          mkdir -p /tmp/kitchen/results
          #{"mkdir -p /tmp/kitchen/config" unless config[:override_package_config]}
          if [ -f /etc/systemd/system/hab-sup.service ]
          then
            echo "Hab-sup service already exists"
          else
            echo "Starting hab-sup service install"
            hab license accept
            if ! id -u hab > /dev/null 2>&1; then
              echo "Adding hab user"
              sudo -E groupadd hab
            fi
            if ! id -g hab > /dev/null 2>&1; then
              echo "Adding hab group"
              sudo -E useradd -g hab hab
            fi
            echo [Unit] | sudo tee /etc/systemd/system/hab-sup.service
            echo Description=The Chef Habitat Supervisor | sudo tee -a /etc/systemd/system/hab-sup.service
            echo [Service] | sudo tee -a /etc/systemd/system/hab-sup.service
            echo Environment="HAB_BLDR_URL=#{config[:depot_url]}" | sudo tee -a /etc/systemd/system/hab-sup.service
            echo Environment="HAB_LICENSE=#{config[:hab_license]}" | sudo tee -a /etc/systemd/system/hab-sup.service
            echo "ExecStart=/bin/hab sup run #{supervisor_options}" | sudo tee -a /etc/systemd/system/hab-sup.service
            echo [Install] | sudo tee -a /etc/systemd/system/hab-sup.service
            echo WantedBy=default.target | sudo tee -a /etc/systemd/system/hab-sup.service
            sudo -E systemctl daemon-reload
            sudo -E systemctl start hab-sup
            sudo -E systemctl enable hab-sup
          fi
        LINUX_SERVICE_SETUP
      end

      def resolve_results_directory
        return config[:results_directory] unless config[:results_directory].nil?

        results_in_current = File.join(config[:kitchen_root], "results")
        results_in_parent = File.join(config[:kitchen_root], "../results")
        results_in_grandparent = File.join(config[:kitchen_root], "../../results")

        if Dir.exist?(results_in_current)
          results_in_current
        elsif Dir.exist?(results_in_parent)
          results_in_parent
        elsif Dir.exist?(results_in_grandparent)
          results_in_grandparent
        end
      end

      def copy_package_config_from_override_to_sandbox
        return if config[:config_directory].nil?
        return unless config[:override_package_config]

        local_config_dir = File.join(config[:kitchen_root], config[:config_directory])
        return unless Dir.exist?(local_config_dir)

        sandbox_config_dir = File.join(sandbox_path, "config")
        FileUtils.copy_entry(local_config_dir, sandbox_config_dir)
      end

      def copy_results_to_sandbox
        return if config[:artifact_name].nil? && !config[:install_latest_artifact]

        results_dir = resolve_results_directory
        return if results_dir.nil?

        FileUtils.mkdir_p(File.join(sandbox_path, "results"))
        FileUtils.cp(
          File.join(results_dir, config[:install_latest_artifact] ? latest_artifact_name : config[:artifact_name]),
          File.join(sandbox_path, "results"),
          preserve: true
        )
      end

      def full_user_toml_path
        File.join(File.join(config[:kitchen_root], config[:config_directory]), config[:user_toml_name])
      end

      def sandbox_user_toml_path
        File.join(File.join(sandbox_path, "config"), "user.toml")
      end

      def copy_user_toml_to_sandbox
        return if config[:config_directory].nil?
        return unless File.exist?(full_user_toml_path)

        FileUtils.mkdir_p(File.join(sandbox_path, "config"))
        debug("Copying user.toml from #{full_user_toml_path} to #{sandbox_user_toml_path}")
        FileUtils.cp(full_user_toml_path, sandbox_user_toml_path)
      end

      def latest_artifact_name
        results_dir = resolve_results_directory
        return if results_dir.nil?

        if config[:install_latest_artifact]
          if config[:package_origin].nil? || config[:package_name].nil?
            raise UserError,
                "You must specify a 'package_origin' and 'package_name' to use the 'install_latest_artifact' option"
          end
        end

        artifact_path = Dir.glob(File.join(results_dir, "#{config[:package_origin]}-#{config[:package_name]}-*.hart")).max_by { |f| File.mtime(f) }
        File.basename(artifact_path)
      end

      def copy_user_toml_to_service_directory
        return unless !config[:config_directory].nil? && File.exist?(full_user_toml_path)

        if windows_os?
          <<~PWSH
            New-Item -Path c:\\hab\\user\\#{config[:package_name]}\\config -ItemType Directory -Force  | Out-Null
            Copy-Item -Path #{File.join(File.join(config[:root_path], "config"), "user.toml")} -Destination c:\\hab\\user\\#{config[:package_name]}\\config\\user.toml -Force
          PWSH
        else
          <<~BASH
            sudo -E mkdir -p /hab/user/#{config[:package_name]}/config
            sudo -E cp #{File.join(File.join(config[:root_path], "config"), "user.toml")} /hab/user/#{config[:package_name]}/config/user.toml
          BASH
        end
      end

      def remove_previous_user_toml
        if windows_os?
          <<~REMOVE
            if (Test-Path c:\\hab\\user\\#{config[:package_name]}\\config\\user.toml) {
              Remove-Item -Path c:\\hab\\user\\#{config[:package_name]}\\config\\user.toml -Force
            }
          REMOVE
        else
          <<~REMOVE
            if [ -d "/hab/user/#{config[:package_name]}/config" ]; then
              sudo -E find /hab/user/#{config[:package_name]}/config -name user.toml -delete
            fi
          REMOVE
        end
      end

      def artifact_name_to_package_ident_regex
        /(?<origin>\w+)-(?<name>.*)-(?<version>(\d+)?(\.\d+)?(\.\d+)?(\.\d+)?)-(?<release>\d+)-(?<target>.*)\.hart$/
      end

      def package_ident
        ident = "#{config[:package_origin]}/" \
                "#{config[:package_name]}/" \
                "#{config[:package_version]}/" \
                "#{config[:package_release]}".chomp("/").chomp("/")
        @pkg_ident = ident
      end

      def get_artifact_name
        artifact_name = ""
        if config[:install_latest_artifact]
          artifact_name = latest_artifact_name
        elsif !config[:install_latest_artifact] && !config[:artifact_name].nil?
          artifact_name = config[:artifact_name]
        else
          return
        end
        ident = artifact_name_to_package_ident_regex.match(artifact_name)
        config[:package_origin] = ident["origin"]
        config[:package_name] = ident["name"]
        config[:package_version] = ident["version"]
        config[:package_release] = ident["release"]
        File.join(File.join(config[:root_path], "results"), artifact_name)
      end

      def supervisor_options
        options = ""
        options += " --listen-ctl #{config[:hab_sup_listen_ctl]}" unless config[:hab_sup_listen_ctl].nil?
        options += " --listen-gossip #{config[:hab_sup_listen_gossip]}" unless config[:hab_sup_listen_gossip].nil?
        options += " --config-from #{File.join(config[:root_path], "config/")}" if config[:override_package_config]
        options += config[:hab_sup_bind].map { |b| " --bind #{b}" }.join(" ") if config[:hab_sup_bind].any?
        options += config[:hab_sup_peer].map { |p| " --peer #{p}" }.join(" ") if config[:hab_sup_peer].any?
        options += " --group #{config[:hab_sup_group]}" unless config[:hab_sup_group].nil?
        options += " --ring #{config[:hab_sup_ring]}" unless config[:hab_sup_ring].nil?
        options += " --topology #{config[:service_topology]}" unless config[:service_topology].nil?
        options += " --strategy #{config[:service_update_strategy]}" unless config[:service_update_strategy].nil?
        options += " --channel #{config[:channel]}" unless config[:channel].nil?
        options += " --event-stream-application #{config[:event_stream_application]}" unless config[:event_stream_application].nil?
        options += " --event-stream-environment #{config[:event_stream_environment]}" unless config[:event_stream_environment].nil?
        options += " --event-stream-site #{config[:event_stream_site]}" unless config[:event_stream_site].nil?
        options += " --event-stream-url #{config[:event_stream_url]}" unless config[:event_stream_url].nil?
        options += " --event-stream-token #{config[:event_stream_token]}" unless config[:event_stream_token].nil?

        options
      end

      def service_options
        options = ""
        options += config[:hab_sup_bind].map { |b| " --bind #{b}" }.join(" ") if config[:hab_sup_bind].any?
        options += " --group #{config[:hab_sup_group]}" unless config[:hab_sup_group].nil?
        options += " --topology #{config[:service_topology]}" unless config[:service_topology].nil?
        options += " --strategy #{config[:service_update_strategy]}" unless config[:service_update_strategy].nil?
        options += " --channel #{config[:channel]}" unless config[:channel].nil?

        options
      end
    end
  end
end
