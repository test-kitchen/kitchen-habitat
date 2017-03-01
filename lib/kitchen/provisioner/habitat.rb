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
      #default_config :hab_sup_
      default_config :package_origin, "core"
      default_config :package_name do |provisioner|
        provisioner.instance.suite.name
      end

      default_config :user_toml_path

      def install_command
        if instance.platform == "windows"
          raise "Need to fill in some implementation here."
        else
          wrap_shell_code <<-BASH
          #{export_hab_orgin}
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
        wrap_shell_code "id -u hab || sudo useradd hab"
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
        #{export_hab_orgin}
        sudo screen -mdS \"#{clean_package_name}\" hab-sup start #{package_ident} #{supervisor_options}
        RUN

        info("Running #{package_ident}.")
        wrap_shell_code run
      end

      private

      def copy_results_to_sandbox
        FileUtils.mkdir_p(File.join(sandbox_path, "results/"))
        FileUtils.cp(
          File.join(File.dirname(__FILE__), ""),
          File.join(sandbox_path, ""),
          preserve: true
        )
      end

      def install_service_package 
        ""
      end

      def export_hab_orgin
        return if config[:depot_url].nil?
        "export HAB_ORIGIN=#{config[:depot_url]}"
      end

      def install_supervisor_command
        "sudo hab pkg install #{config[:hab_sup]}"
      end

      def binlink_supervisor_command
        "sudo hab pkg binlink #{config[:hab_sup]} hab-sup"
      end

      def archive_name_to_package_ident(filename)
        filename
      end

      def package_ident
        @pkg_ident ||= "#{config[:package_origin]}/#{config[:package_name]}"
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
