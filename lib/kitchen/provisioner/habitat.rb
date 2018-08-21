#
# Author:: Steven Murawski (<steven.murawski@gmail.com>)
#
# Copyright (C) 2017 Steven Murawski
#
# Licensed under the MIT License.
# See LICENSE for more details

require "fileutils"
require "pathname"
require "kitchen/provisioner/base"
require "kitchen/util"

module Kitchen
  module Provisioner
    class Habitat < Base
      kitchen_provisioner_api_version 2

      default_config :depot_url, nil
      default_config :hab_version, "latest"
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

      # local stuffs to copy
      default_config :results_directory, nil
      default_config :config_directory, nil
      default_config :user_toml_name, "user.toml"
      default_config :override_package_config, false

      # experimental
      default_config :use_screen, false

      def finalize_config!(instance)
        # Check to see if a package ident was specified for package name and be helpful
        unless config[:package_name].nil? || (config[:package_name] =~ /\//).nil?
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
        raise "Need to fill in some implementation here." if instance.platform == "windows"

        version = " -v #{config[:hab_version]}" unless config[:hab_version].eql?('latest')

        wrap_shell_code <<-BASH
        #{export_hab_bldr_url}
        if command -v hab >/dev/null 2>&1
        then
          echo "Habitat CLI already installed."
        else
          curl -o /tmp/install.sh 'https://raw.githubusercontent.com/habitat-sh/habitat/master/components/hab/install.sh'
          sudo -E bash /tmp/install.sh#{version}
        fi
        BASH
      end

      def init_command
        wrap_shell_code <<-EOH
          id -u hab >/dev/null 2>&1 || sudo -E useradd hab >/dev/null 2>&1
          rm -rf /tmp/kitchen
          mkdir -p /tmp/kitchen/results
          #{'mkdir -p /tmp/kitchen/config' unless config[:override_package_config]}
        EOH
      end

      def create_sandbox
        super
        copy_results_to_sandbox
        copy_user_toml_to_sandbox
        copy_package_config_from_override_to_sandbox
      end

      def prepare_command
        wrap_shell_code <<-EOH
          #{export_hab_bldr_url}
          #{install_supervisor_command}
          #{binlink_supervisor_command}
          #{install_service_package}
          #{remove_previous_user_toml}
          #{copy_user_toml_to_service_directory}
          EOH
      end

      def run_command
        run = <<-RUN
        #{export_hab_bldr_url}
        #{clean_up_screen_sessions}
        #{clean_up_previous_supervisor}
        echo "Running #{package_ident}."
        #{run_package_in_background}
        RUN

        wrap_shell_code run
      end

      private

      def clean_up_screen_sessions
        return unless config[:use_screen]
        <<-CLEAN
        if sudo -E screen -ls | grep -q #{clean_package_name}
          then
            echo "Killing previous supervisor session."
            sudo -E screen -S \"#{clean_package_name}\" -X quit > /dev/null
            echo "Removing dead session."
            sudo -E screen -wipe > /dev/null
        fi
        CLEAN
      end

      def clean_up_previous_supervisor
        return if config[:use_screen]
        <<-EOH
        [ -f ./run.pid ] && echo "Removing previous supervisor and unloading package. "
        [ -f ./run.pid ] && sudo -E hab svc unload #{package_ident}
        [ -f ./run.pid ] && sleep 5
        [ -f ./run.pid ] && sudo -E kill $(cat run.pid)
        [ -f ./run.pid ] && sleep 5
        EOH
      end

      def run_package_in_background
        if config[:use_screen]
          "sudo -E screen -mdS \"#{clean_package_name}\" hab start #{package_ident} #{supervisor_options}"
        else
          <<-RUN
          [ -f ./run.pid ] && rm -f run.pid
          [ -f ./nohup.out ] && rm -f nohup.out

          nohup sudo -E hab sup run #{supervisor_options} & echo $! > run.pid

          until sudo -E hab svc status
          do
            sleep 1
          done

          sudo -E hab svc load #{package_ident} #{service_options}

          until sudo -E hab svc status | grep #{package_ident}
          do
            sleep 1
          done

          [ -f ./nohup.out ] && cat nohup.out || (echo "Failed to start the supervisor." && exit 1)
          RUN
        end
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

      def install_service_package
        return unless config[:install_latest_artifact] || !config[:artifact_name].nil?

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

        artifact_path = File.join(File.join(config[:root_path], "results"), artifact_name)
        "sudo -E hab pkg install #{artifact_path}"
      end

      def latest_artifact_name
        results_dir = resolve_results_directory
        return if results_dir.nil?

        artifact_path = Dir.glob(File.join(results_dir, "#{config[:package_origin]}-#{config[:package_name]}-*.hart")).max_by { |f| File.mtime(f) }

        File.basename(artifact_path)
      end

      def copy_user_toml_to_service_directory
        return unless !config[:config_directory].nil? && File.exist?(full_user_toml_path)
        <<-EOH
          sudo -E mkdir -p /hab/svc/#{config[:package_name]}
          sudo -E cp #{File.join(File.join(config[:root_path], 'config'), 'user.toml')} /hab/svc/#{config[:package_name]}/user.toml
        EOH
      end

      def remove_previous_user_toml
        <<-REMOVE
        if [ -d "/hab/svc/#{config[:package_name]}" ]; then
          sudo -E find /hab/svc/#{config[:package_name]} -name user.toml -delete
        fi
        REMOVE
      end

      def export_hab_bldr_url
        return if config[:depot_url].nil?
        "export HAB_BLDR_URL=#{config[:depot_url]}"
      end

      def install_supervisor_command
        "sudo -E hab pkg install #{hab_sup_ident}"
      end

      def binlink_supervisor_command
        "sudo -E hab pkg binlink #{hab_sup_ident} hab-sup"
      end

      def artifact_name_to_package_ident_regex
        /(?<origin>\w+)-(?<name>.*)-(?<version>(\d+)?(\.\d+)?(\.\d+)?(\.\d+)?)-(?<release>\d+)-(?<target>.*)\.hart$/
      end

      def hab_sup_ident
        ident = "#{config[:hab_sup_origin]}/" \
                "#{config[:hab_sup_name]}/" \
                "#{config[:hab_sup_version]}/" \
                "#{config[:hab_sup_release]}".chomp("/").chomp("/")
        @sup_ident ||= ident
      end

      def package_ident
        ident = "#{config[:package_origin]}/" \
                "#{config[:package_name]}/" \
                "#{config[:package_version]}/" \
                "#{config[:package_release]}".chomp("/").chomp("/")
        @pkg_ident = ident
      end

      def clean_package_name
        @clean_name ||= "#{config[:package_origin]}-#{config[:package_name]}"
      end

      def supervisor_options
        options = ""
        options += " --listen-ctl #{config[:hab_sup_listen_ctl]}" unless config[:hab_sup_listen_ctl].nil?
        options += " --listen-gossip #{config[:hab_sup_listen_gossip]}" unless config[:hab_sup_listen_gossip].nil?
        options += " --config-from #{File.join(config[:root_path], 'config/')}" if config[:override_package_config]
        options += config[:hab_sup_bind].map { |b| " --bind #{b}" }.join(" ") if config[:hab_sup_bind].any?
        options += config[:hab_sup_peer].map { |p| " --peer #{p}" }.join(" ") if config[:hab_sup_peer].any?
        options += " --group #{config[:hab_sup_group]}" unless config[:hab_sup_group].nil?
        options += " --ring #{config[:hab_sup_ring]}" unless config[:hab_sup_ring].nil?
        options += " --topology #{config[:service_topology]}" unless config[:service_topology].nil?
        options += " --strategy #{config[:service_update_strategy]}" unless config[:service_update_strategy].nil?
        options += " --channel #{config[:channel]}" unless config[:channel].nil?

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
