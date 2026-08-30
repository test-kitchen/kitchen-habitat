#
# Author:: Steven Murawski (<steven.murawski@gmail.com>)
#
# Copyright (C) 2017 Steven Murawski
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

require "fileutils" unless defined?(FileUtils)
require "pathname" unless defined?(Pathname)
require "kitchen/provisioner/base"
require "kitchen/util"

module Kitchen
  # Test Kitchen's provisioner plugins.
  module Provisioner
    # Test Kitchen provisioner that converges an instance with
    # {https://habitat.sh Habitat}.
    #
    # A converge installs the +hab+ CLI, starts a supervisor, uploads any
    # local artifact and configuration, then installs the package under test
    # and loads it as a service. The instance itself is supplied by whichever
    # Test Kitchen driver is configured; this provisioner only provisions.
    #
    # Configuration options fall into five groups:
    #
    # * *CLI* -- +hab_license+, +hab_version+, +hab_channel+, +depot_url+
    # * *Supervisor* -- the +hab_sup_*+ options, which become +hab sup run+ flags
    # * *Service* -- +package_*+, +channel+, +service_*+
    # * *Local files* -- +artifact_name+, +install_latest_artifact+,
    #   +results_directory+, +config_directory+, +user_toml_name+,
    #   +override_package_config+
    # * *Event stream* -- the +event_stream_*+ options, for Chef Automate
    #
    # See the README for the full reference, including the options that are
    # currently accepted but not read.
    #
    # @see https://habitat.sh Habitat
    class Habitat < Base
      kitchen_provisioner_api_version 2

      # Origin of the supervisor package used when none is configured.
      DEFAULT_SUP_ORIGIN = "core".freeze

      # Name of the supervisor package used when none is configured.
      DEFAULT_SUP_NAME = "hab-sup".freeze

      default_config :depot_url, nil
      default_config :hab_license, nil
      default_config :hab_version, "latest"
      default_config :hab_channel, "stable"
      default_config :hab_sup_origin, DEFAULT_SUP_ORIGIN
      default_config :hab_sup_name, DEFAULT_SUP_NAME
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

      # Normalizes the package identity options before Test Kitchen freezes
      # the configuration.
      #
      # Three shorthands are expanded here so the rest of the provisioner can
      # assume it has separate origin, name, version, and release values:
      #
      # * a +package_name+ given as a full identifier, e.g. +core/redis/4.0.14+
      # * a +hab_sup_artifact_name+ +.hart+ filename
      # * an +artifact_name+ +.hart+ filename
      #
      # @param instance [Kitchen::Instance] the instance being configured
      # @return [self]
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

      # Shell code that installs the +hab+ CLI on the instance.
      #
      # Idempotent: if +hab+ is already on the PATH the install is skipped, so
      # this is safe to re-run against a converged machine.
      #
      # @return [String] platform-appropriate shell code, ready to execute
      def install_command
        if windows_os?
          wrap_shell_code(windows_install_cmd)
        else
          wrap_shell_code(linux_install_cmd)
        end
      end

      # Shell code that installs and starts the Habitat supervisor.
      #
      # On Linux this writes a +hab-sup+ systemd unit and enables it. On
      # Windows it installs +core/windows-service+ and patches its launcher
      # arguments. Both paths are skipped when the supervisor already exists.
      #
      # @return [String] platform-appropriate shell code, ready to execute
      def init_command
        if windows_os?
          wrap_shell_code(windows_install_service)
        else
          wrap_shell_code(linux_install_service)
        end
      end

      # Stages the local files the instance will need into the sandbox.
      #
      # Copies in the +.hart+ artifact under test and, when a
      # +config_directory+ is configured, the +user.toml+ and any package
      # configuration that overrides what is baked into the package.
      #
      # @return [void]
      def create_sandbox
        super
        copy_results_to_sandbox
        copy_user_toml_to_sandbox
        copy_package_config_from_override_to_sandbox
      end

      # Shell code run on the instance after the sandbox is uploaded but
      # before {#run_command}.
      #
      # Replaces any +user.toml+ left over from a previous converge with the
      # one just uploaded, so a changed +user.toml+ takes effect.
      #
      # @return [String] platform-appropriate shell code, ready to execute
      def prepare_command
        debug("Prepare command is running")
        wrap_shell_code <<~PREPARE
          #{remove_previous_user_toml}
          #{copy_user_toml_to_service_directory}
        PREPARE
      end

      # Shell code that installs the package under test and loads it as a
      # service.
      #
      # The package is only loaded with +hab svc load+ if it ships a run
      # hook -- either +hooks/run+ or a +run+ file in the package root, both
      # of which the supervisor accepts -- so library packages converge
      # cleanly without a service. After
      # loading, this polls +hab svc status+ until the service appears, giving
      # up after +service_load_timeout+ seconds.
      #
      # @return [String] platform-appropriate shell code, ready to execute
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
            $PkgPath = hab pkg path #{target_ident}
            if (@("hooks\\run", "hooks\\run.ps1", "run", "run.ps1") | Where-Object { Test-Path -Path (Join-Path $PkgPath $_) }) {
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
            pkg_path="$(sudo hab pkg path #{target_ident})"
            if [ -f "$pkg_path/hooks/run" ] || [ -f "$pkg_path/run" ]
              then
                sudo -E hab svc load #{target_ident} #{service_options} --force
                timer=0
                until sudo -E hab svc status | grep #{target_ident}
                  do
                    if [ "$timer" -ge #{config[:service_load_timeout]} ]; then
                      echo "Timed out after #{config[:service_load_timeout]}s waiting for #{target_ident} to load"
                      exit 1
                    fi
                    sleep 1
                    timer=$((timer + 1))
                  done
            fi
          BASH
        end
      end

      private

      # PowerShell that installs the +hab+ CLI from the official install
      # script, honouring +hab_channel+ and +hab_version+.
      #
      # @return [String] PowerShell source
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

      # Bash that installs the +hab+ CLI from the official install script.
      #
      # +hab_version+ is passed as +-v+ unless it is +"latest"+, which the
      # install script treats as the default.
      #
      # @return [String] Bash source
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

      # PowerShell that installs the Habitat Windows service and points its
      # launcher at the configured supervisor options.
      #
      # The options cannot be passed on a command line here, so they are
      # written into +HabService.dll.config+ before the service is started.
      #
      # @return [String] PowerShell source
      def windows_install_service
        <<~WINDOWS_SERVICE_SETUP
          New-Item -Path C:\\Windows\\Temp\\kitchen -ItemType Directory -Force | Out-Null
          #{"New-Item -Path C:\\Windows\\Temp\\kitchen\\config -ItemType Directory -Force | Out-Null" unless config[:override_package_config]}
          if (!($env:Path | Select-String "Habitat")) {
            $env:Path += ";C:\\ProgramData\\Habitat"
          }
          if (!(Get-Service -Name Habitat -ErrorAction Ignore)) {
            hab license accept#{install_supervisor_command("  ")}
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

      # Bash that creates the +hab+ user and group, writes a +hab-sup+
      # systemd unit, and starts it.
      #
      # +depot_url+ and +hab_license+ are passed to the supervisor as the
      # +HAB_BLDR_URL+ and +HAB_LICENSE+ environment variables.
      #
      # @return [String] Bash source
      def linux_install_service
        <<~LINUX_SERVICE_SETUP
          rm -rf /tmp/kitchen
          mkdir -p /tmp/kitchen/results
          #{"mkdir -p /tmp/kitchen/config" unless config[:override_package_config]}
          if [ -f /etc/systemd/system/hab-sup.service ]
          then
            echo "Hab-sup service already exists"
          else
            echo "Starting hab-sup service install"
            hab license accept#{install_supervisor_command("  ")}
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
            echo [Service] | sudo tee -a /etc/systemd/system/hab-sup.service#{supervisor_environment_lines("  ")}
            echo "ExecStart=/bin/hab sup run #{supervisor_options}" | sudo tee -a /etc/systemd/system/hab-sup.service
            echo [Install] | sudo tee -a /etc/systemd/system/hab-sup.service
            echo WantedBy=default.target | sudo tee -a /etc/systemd/system/hab-sup.service
            sudo -E systemctl daemon-reload
            sudo -E systemctl start hab-sup
            sudo -E systemctl enable hab-sup
          fi
        LINUX_SERVICE_SETUP
      end

      # Locates the directory holding built +.hart+ artifacts.
      #
      # An explicit +results_directory+ wins. Otherwise +results+, then
      # +../results+, then +../../results+ relative to the kitchen root are
      # tried, which covers the usual +hab studio+ layouts.
      #
      # @return [String, nil] the directory, or nil if none was found
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

      # Copies +config_directory+ into the sandbox so the supervisor can be
      # pointed at it with +--config-from+.
      #
      # Does nothing unless +override_package_config+ is set and the directory
      # exists.
      #
      # @return [void]
      def copy_package_config_from_override_to_sandbox
        return if config[:config_directory].nil?
        return unless config[:override_package_config]

        local_config_dir = File.join(config[:kitchen_root], config[:config_directory])
        return unless Dir.exist?(local_config_dir)

        sandbox_config_dir = File.join(sandbox_path, "config")
        FileUtils.copy_entry(local_config_dir, sandbox_config_dir)
      end

      # Copies the +.hart+ under test into the sandbox.
      #
      # Does nothing unless +artifact_name+ or +install_latest_artifact+ asked
      # for a local artifact.
      #
      # @return [void]
      def copy_results_to_sandbox
        artifacts = artifacts_to_upload
        return if artifacts.empty?

        results_dir = resolve_results_directory
        return if results_dir.nil?

        FileUtils.mkdir_p(File.join(sandbox_path, "results"))
        artifacts.each do |artifact|
          FileUtils.cp(
            File.join(results_dir, artifact),
            File.join(sandbox_path, "results"),
            preserve: true
          )
        end
      end

      # The +.hart+ filenames that need uploading.
      #
      # The service artifact under test, plus a custom supervisor artifact
      # when one is configured. Both are read from the results directory.
      #
      # @return [Array<String>] artifact basenames, empty when none apply
      def artifacts_to_upload
        artifacts = []

        if config[:install_latest_artifact]
          artifacts << latest_artifact_name
        elsif config[:artifact_name]
          artifacts << config[:artifact_name]
        end

        artifacts << config[:hab_sup_artifact_name] if config[:hab_sup_artifact_name]
        artifacts.compact.uniq
      end

      # Local path to the +user.toml+ to upload.
      #
      # @return [String] path under the configured +config_directory+
      def full_user_toml_path
        File.join(File.join(config[:kitchen_root], config[:config_directory]), config[:user_toml_name])
      end

      # Path the +user.toml+ is staged at inside the sandbox.
      #
      # Always named +user.toml+ regardless of +user_toml_name+, since that is
      # the name Habitat expects on the instance.
      #
      # @return [String]
      def sandbox_user_toml_path
        File.join(File.join(sandbox_path, "config"), "user.toml")
      end

      # Copies the configured +user.toml+ into the sandbox.
      #
      # Does nothing when no +config_directory+ is set or the file is absent.
      #
      # @return [void]
      def copy_user_toml_to_sandbox
        return if config[:config_directory].nil?
        return unless File.exist?(full_user_toml_path)

        FileUtils.mkdir_p(File.join(sandbox_path, "config"))
        debug("Copying user.toml from #{full_user_toml_path} to #{sandbox_user_toml_path}")
        FileUtils.cp(full_user_toml_path, sandbox_user_toml_path)
      end

      # Finds the most recently modified +.hart+ matching the configured
      # origin and name.
      #
      # @return [String, nil] the artifact's basename, or nil when no results
      #   directory could be resolved
      # @raise [Kitchen::UserError] if +install_latest_artifact+ is set without
      #   both +package_origin+ and +package_name+, which are what the
      #   filename glob is built from
      def latest_artifact_name
        results_dir = resolve_results_directory
        return if results_dir.nil?

        if config[:install_latest_artifact]
          if config[:package_origin].nil? || config[:package_name].nil?
            raise UserError,
              "You must specify a 'package_origin' and 'package_name' to use the 'install_latest_artifact' option"
          end
        end

        glob = File.join(results_dir, "#{config[:package_origin]}-#{config[:package_name]}-*.hart")
        artifact_path = Dir.glob(glob).max_by { |f| File.mtime(f) }
        if artifact_path.nil?
          raise UserError,
            "No Habitat artifact matching #{File.basename(glob)} was found in #{results_dir}. " \
            "Build the package first, or point 'results_directory' at the directory holding its .hart file."
        end

        File.basename(artifact_path)
      end

      # Shell code that installs the uploaded +user.toml+ into the service's
      # +/hab/user+ configuration directory on the instance.
      #
      # @return [String, nil] shell source, or nil when there is no
      #   +user.toml+ to install
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

      # Shell code that deletes a +user.toml+ left behind by an earlier
      # converge, so a removed setting does not linger.
      #
      # @return [String] platform-appropriate shell source
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

      # Pattern that splits a +.hart+ filename into its package identifier
      # parts.
      #
      # Named captures: +origin+, +name+, +version+, +release+, +target+. For
      # +core-redis-4.0.14-20180404215500-x86_64-linux.hart+ that yields origin
      # +core+, name +redis+, version +4.0.14+, release +20180404215500+.
      #
      # @return [Regexp]
      def artifact_name_to_package_ident_regex
        /(?<origin>\w+)-(?<name>.*)-(?<version>(\d+)?(\.\d+)?(\.\d+)?(\.\d+)?)-(?<release>\d+)-(?<target>.*)\.hart$/
      end

      # Builds the Habitat package identifier for the configured package.
      #
      # Trailing separators are trimmed, so an origin and name with no version
      # or release yields +origin/name+ rather than +origin/name//+.
      #
      # @return [String] a package identifier such as +core/redis+
      def package_ident
        "#{config[:package_origin]}/" \
          "#{config[:package_name]}/" \
          "#{config[:package_version]}/" \
          "#{config[:package_release]}".chomp("/").chomp("/")
      end

      # Resolves which local artifact to install, and back-fills the package
      # identity options from its filename.
      #
      # @return [String, nil] the artifact's path on the instance, or nil when
      #   no local artifact was requested
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

      # Package identifier for the supervisor to run.
      #
      # Built from the +hab_sup_*+ identity options, which
      # {#finalize_config!} also fills in from +hab_sup_artifact_name+ when
      # one is given. Trailing parts are omitted when unset, so the default
      # is simply +core/hab-sup+.
      #
      # @return [String] e.g. +core/hab-sup+ or +core/hab-sup/1.6.652+
      def hab_sup_ident
        [
          config[:hab_sup_origin],
          config[:hab_sup_name],
          config[:hab_sup_version],
          config[:hab_sup_release],
        ].compact.reject { |part| part.to_s.empty? }.join("/")
      end

      # Whether a supervisor other than the stock one was asked for.
      #
      # Only then is a supervisor package installed, so a run that does not
      # configure one behaves exactly as before.
      #
      # @return [Boolean]
      def custom_supervisor?
        return true unless config[:hab_sup_artifact_name].nil?
        return true unless config[:hab_sup_version].nil? && config[:hab_sup_release].nil?

        config[:hab_sup_origin] != DEFAULT_SUP_ORIGIN || config[:hab_sup_name] != DEFAULT_SUP_NAME
      end

      # What +hab pkg install+ should be pointed at for the supervisor.
      #
      # A local artifact is installed from the path it was uploaded to;
      # otherwise the package identifier is installed from the depot.
      #
      # @return [String] an artifact path or a package identifier
      def supervisor_install_source
        if config[:hab_sup_artifact_name]
          File.join(config[:root_path], "results", config[:hab_sup_artifact_name])
        else
          hab_sup_ident
        end
      end

      # Shell code installing the requested supervisor package.
      #
      # Returned with a leading newline so it can be appended to the previous
      # line of a heredoc. That keeps the generated script free of a stray
      # blank line on the far more common path where no custom supervisor is
      # configured and this returns nothing at all.
      #
      # @param indent [String] indentation to match the surrounding script
      # @return [String] the install command, or an empty string when the
      #   stock supervisor is being used
      def install_supervisor_command(indent = "")
        return "" unless custom_supervisor?

        "\n#{indent}hab pkg install #{supervisor_install_source} --force"
      end

      # The +Environment=+ lines for the generated +hab-sup+ systemd unit.
      #
      # Only options that were actually configured are emitted. An empty
      # +HAB_BLDR_URL+ is not the same as an unset one -- it overrides the
      # +hab+ CLI's own default with a URL that cannot be parsed -- so the
      # line is omitted rather than written blank.
      #
      # Returned with a leading newline so it can be appended to the previous
      # line of the heredoc, keeping the generated script free of blank lines.
      #
      # @param indent [String] indentation to match the surrounding script
      # @return [String] zero or more +echo ... | sudo tee -a+ lines
      def supervisor_environment_lines(indent = "")
        {
          "HAB_BLDR_URL" => config[:depot_url],
          "HAB_LICENSE" => config[:hab_license],
        }.reject { |_name, value| value.nil? || value.to_s.empty? }
          .map do |name, value|
            "\n#{indent}echo Environment=\"#{name}=#{value}\" | " \
              "sudo tee -a /etc/systemd/system/hab-sup.service"
          end.join
      end

      # Builds the flag string passed to +hab sup run+.
      #
      # Only options that were actually set are emitted, so an unset option
      # leaves Habitat's own default in place.
      #
      # @return [String] a leading-space-separated flag string, empty when
      #   nothing is configured
      def supervisor_options
        options = ""
        options += " --listen-ctl #{config[:hab_sup_listen_ctl]}" unless config[:hab_sup_listen_ctl].nil?
        options += " --listen-http #{config[:hab_sup_listen_http]}" unless config[:hab_sup_listen_http].nil?
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

      # Builds the flag string passed to +hab svc load+.
      #
      # A subset of {#supervisor_options}: the flags that belong to a service
      # rather than to the supervisor process.
      #
      # @return [String] a leading-space-separated flag string, empty when
      #   nothing is configured
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
