#
# Author:: Steven Murawski (<steven.murawski@gmail.com>)
#
# Copyright (C) 2014 Steven Murawski
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
      default_config :hab_sup, "core/hab-sup"

      # hab-sup manager options
      default_config :hab_sup_listen_http, nil
      default_config :hab_sup_listen_gossip, nil

      # hab-sup service options
      #default_config :
      default_config :artifact_name
      default_config :package_origin, "core"
      default_config :package_name do |provisioner|
        provisioner.instance.suite.name
      end
      default_config :package_version
      default_config :package_timestamp

      default_config :user_toml_path

      def finalize_config!(instance)
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
        wrap_shell_code "id -u hab > /dev/null || sudo useradd hab > /dev/null"
      end

      def create_sandbox
        super
        copy_results_to_sandbox
      end

      def prepare_command
        wrap_shell_code <<-EOH
          #{export_hab_origin}
          #{install_supervisor_command}
          #{binlink_supervisor_command}
          #{install_service_package}
          EOH
      end

      def run_command
        run = <<-RUN
        if sudo screen -ls | grep -q #{clean_package_name}
          then
            echo "Killing previous supervisor session."
            sudo screen -S \"#{clean_package_name}\" -X quit > /dev/null
            echo "Removing dead session."
            sudo screen -wipe > /dev/null
        fi
        #{export_hab_origin}
        echo "Running #{package_ident}."
        sudo screen -mdS \"#{clean_package_name}\" hab-sup start #{package_ident} #{supervisor_options}
        RUN

        wrap_shell_code run
      end

      private

      def copy_results_to_sandbox
        FileUtils.mkdir_p(File.join(sandbox_path, "results"))
        FileUtils.cp_r(
          File.join(config[:kitchen_root], "/results"),
          File.join(sandbox_path, "results"),
          preserve: true
        )
      end

      def install_service_package
        return if config[:artifact_name].nil?
        "sudo hab pkg install #{File.join(File.join(config[:root_path], "results"), config[:artifact_name])}"
      end

      def export_hab_origin
        return if config[:depot_url].nil?
        "export HAB_ORIGIN=#{config[:depot_url]}"
      end

      def install_supervisor_command
        "sudo hab pkg install #{config[:hab_sup]}"
      end

      def binlink_supervisor_command
        "sudo hab pkg binlink #{config[:hab_sup]} hab-sup"
      end

      def artifact_name_to_package_ident_regex
        /(?<origin>\w+)-(?<name>.*)-(?<version>(\d+)?(\.\d+)?(\.\d+)?(\.\d+)?)-(?<timestamp>\d+)-(?<target>.*)\.hart$/
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
        options = "#{'--listen-gossip' + config[:hab_sup_listen_gossip] unless config[:hab_sup_listen_gossip].nil?} "  \
        "#{'--listen-http' + config[:hab_sup_listen_http] unless config[:hab_sup_listen_http].nil?} "  \
        ""
        options.strip
      end
    end
  end
end
