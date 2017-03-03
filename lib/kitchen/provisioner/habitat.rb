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
      default_config :hab_sup_origin, "core"
      default_config :hab_sup_name, "hab-sup"
      default_config :hab_sup_version, nil
      default_config :hab_sup_timestamp, nil
      default_config :hab_sup_artifact_name, nil

      # hab-sup manager options
      default_config :hab_sup_listen_http, nil
      default_config :hab_sup_listen_gossip, nil
      default_config :hab_sup_peer, []
      default_config :hab_sup_bind, []

      # hab-sup service options
      default_config :artifact_name, nil
      default_config :package_origin, "core"
      default_config :package_name do |provisioner|
        provisioner.instance.suite.name
      end
      default_config :package_version, nil
      default_config :package_timestamp, nil

      # local stuffs to copy
      default_config :results_directory, nil
      default_config :config_directory, nil
      default_config :user_toml_name, "user.toml"
      default_config :override_package_config, false

      # experimental
      default_config :use_screen, false

      def finalize_config!(instance)
        unless config[:hab_sup_artifact_name].nil?
          ident = artifact_name_to_package_ident_regex.match(config[:hab_sup_artifact_name])
          config[:hab_sup_origin] = ident["origin"]
          config[:hab_sup_name] = ident["name"]
          config[:hab_sup_version] = ident["version"]
          config[:hab_sup_timestamp] = ident["timestamp"]
        end

        unless config[:artifact_name].nil?
          ident = artifact_name_to_package_ident_regex.match(config[:artifact_name])
          config[:package_origin] = ident["origin"]
          config[:package_name] = ident["name"]
          config[:package_version] = ident["version"]
          config[:package_timestamp] = ident["timestamp"]
        end
        super(instance)
      end

      def install_command
        if instance.platform == "windows"
          raise "Need to fill in some implementation here."
        else
          wrap_shell_code <<-BASH
          #{export_hab_origin}
          if command -v hab >/dev/null 2>&1
          then
            echo "Habitat CLI already installed."
          else
            curl 'https://raw.githubusercontent.com/habitat-sh/habitat/master/components/hab/install.sh' | sudo bash
          fi
          BASH
        end
      end

      def init_command
        wrap_shell_code "id -u hab >/dev/null 2>&1 || sudo useradd hab >/dev/null 2>&1"
      end

      def create_sandbox
        super
        copy_results_to_sandbox
        copy_user_toml_to_sandbox
      end

      def prepare_command
        wrap_shell_code <<-EOH
          #{export_hab_origin}
          #{install_supervisor_command}
          #{binlink_supervisor_command}
          #{install_service_package}
          #{remove_previous_user_toml}
          #{copy_user_toml_to_service_directory}
          EOH
      end

      def run_command
        run = <<-RUN
        #{clean_up_screen_sessions}
        #{clean_up_previous_supervisor}
        #{export_hab_origin}
        echo "Running #{package_ident}."

        #{run_package_in_background}        
        RUN

        wrap_shell_code run
      end

      private

      def clean_up_screen_sessions
        return unless config[:use_screen]
        <<-CLEAN
        if sudo screen -ls | grep -q #{clean_package_name}
          then
            echo "Killing previous supervisor session."
            sudo screen -S \"#{clean_package_name}\" -X quit > /dev/null
            echo "Removing dead session."
            sudo screen -wipe > /dev/null
        fi
        CLEAN
      end

      def clean_up_previous_supervisor 
        return if config[:use_screen]
        <<-EOH
        if [ -f "run.pid" ]; then
          kill -9 "$(cat run.pid)" > /dev/null
        fi
        EOH
      end

      def run_package_in_background
        if config[:use_screen]
          "sudo screen -mdS \"#{clean_package_name}\" hab-sup start #{package_ident} #{supervisor_options}"
        else
          <<-RUN
          nohup sudo hab-sup start #{package_ident} #{supervisor_options} & echo $! > run.pid
          sleep 5
          cat nohup.out
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

      def copy_results_to_sandbox
        results_dir = resolve_results_directory
        return if results_dir.nil?
        FileUtils.mkdir_p(File.join(sandbox_path, "results"))
        FileUtils.cp_r(
          results_dir,
          File.join(sandbox_path, "results"),
          preserve: true
        )
      end

      def full_user_toml_path
        File.join(File.join(config[:kitchen_root], config[:config_directory]), config[:user_toml_name])
      end

      def copy_user_toml_to_sandbox
        return if config[:config_directory].nil?
        FileUtils.mkdir_p(File.join(sandbox_path, "config"))
        FileUtils.cp_r(File.join(config[:kitchen_root], config[:config_directory]), File.join(sandbox_path, "config"))
      end

      def install_service_package
        return if config[:artifact_name].nil?
        "sudo hab pkg install #{File.join(File.join(config[:root_path], 'results'), config[:artifact_name])}"
      end

      def copy_user_toml_to_service_directory
        return unless !config[:config_directory].nil? && File.exist?(full_user_toml_path)
        "cp #{File.join(File.join(config[:root_path], 'config'), 'user.toml')} /hab/svc/#{config[:package_name]}/"
      end

      def remove_previous_user_toml
        <<-REMOVE
        if [ -d "/hab/svc/#{config[:package_name]}" ]; then
          sudo find /hab/svc/#{config[:package_name]} -name user.toml -delete
        fi
        REMOVE
      end

      def export_hab_origin
        return if config[:depot_url].nil?
        "export HAB_ORIGIN=#{config[:depot_url]}"
      end

      def install_supervisor_command
        "sudo hab pkg install #{hab_sup_ident}"
      end

      def binlink_supervisor_command
        "sudo hab pkg binlink #{hab_sup_ident} hab-sup"
      end

      def artifact_name_to_package_ident_regex
        /(?<origin>\w+)-(?<name>.*)-(?<version>(\d+)?(\.\d+)?(\.\d+)?(\.\d+)?)-(?<timestamp>\d+)-(?<target>.*)\.hart$/
      end

      def hab_sup_ident
        ident = "#{config[:hab_sup_origin]}/" \
                "#{config[:hab_sup_name]}/" \
                "#{config[:hab_sup_version]}/" \
                "#{config[:hab_sup_timestamp]}".chomp("/").chomp("/")
        @sup_ident ||= ident
      end

      def package_ident
        ident = "#{config[:package_origin]}/" \
                "#{config[:package_name]}/" \
                "#{config[:package_version]}/" \
                "#{config[:package_timestamp]}".chomp("/").chomp("/")
        @pkg_ident ||= ident
      end

      def clean_package_name
        @clean_name ||= "#{config[:package_origin]}-#{config[:package_name]}"
      end

      def supervisor_options
        options = "#{'--listen-gossip ' + config[:hab_sup_listen_gossip] unless config[:hab_sup_listen_gossip].nil?} "  \
        "#{'--listen-http ' + config[:hab_sup_listen_http] unless config[:hab_sup_listen_http].nil?} "  \
        "#{'--config-from ' + File.join(config[:root_path], 'config/') if config[:override_package_config]} "
        options.strip!
        options += config[:hab_sup_bind].map { |b| " --bind #{b}" }.join(" ") if config[:hab_sup_bind].any?
        options += config[:hab_sup_peer].map { |p| " --peer #{p}" }.join(" ") if config[:hab_sup_peer].any?
        options
      end
    end
  end
end
