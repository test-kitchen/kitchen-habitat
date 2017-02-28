# -*- encoding: utf-8 -*-
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
      default_config :package_origin, "core"
      default_config :package_name do |provisioner|
        provisioner.instance.suite.name
      end

      def install_command
        if instance.platform == "windows"
          raise "Need to fill in some implementation here."
        else
          wrap_shell_code <<-BASH
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

      end

      def prepare_command
        wrap_shell_code <<-EOH
          sudo hab pkg install #{config[:hab_sup]}
          sudo hab pkg binlink #{config[:hab_sup]} hab-sup
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
        sudo screen -mdS \"#{clean_package_name}\" hab-sup start #{package_ident}
        RUN
        info("Running #{package_ident}.")
        wrap_shell_code run
      end

      private

      def package_ident
        @pkg_ident ||= "#{config[:package_origin]}/#{config[:package_name]}"
      end

      def clean_package_name
        @clean_name ||= "#{config[:package_origin]}-#{config[:package_name]}"
      end
    end
  end
end
