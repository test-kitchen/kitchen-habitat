# frozen_string_literal: true

require "kitchen/provisioner/habitat"
require "fakefs/safe"

RSpec.describe Kitchen::Provisioner::Habitat do
  include_context "habitat provisioner"

  describe "#windows_install_cmd" do
    it "generates a valid install script" do
      config[:hab_channel] = "stable"
      config[:hab_version] = "1.5.29"
      windows_install_cmd = provisioner.send(
        :windows_install_cmd
      )
      expected_code = <<~PWSH
        if ((Get-Command hab -ErrorAction Ignore).Path) {
          Write-Output "Habitat CLI already installed."
        } else {
          Set-ExecutionPolicy Bypass -Scope Process -Force
          $InstallScript = ((New-Object System.Net.WebClient).DownloadString('https://raw.githubusercontent.com/habitat-sh/habitat/master/components/hab/install.ps1'))
          Invoke-Command -ScriptBlock ([scriptblock]::Create($InstallScript)) -ArgumentList #{config[:hab_channel]}, #{config[:hab_version]}
        }
      PWSH
      expect(windows_install_cmd).to eq(expected_code)
    end
  end

  describe "#linux_install_cmd" do
    it "generates a valid install script" do
      config[:hab_version] = "1.5.29"
      linux_install_cmd = provisioner.send(
        :linux_install_cmd
      )
      expected_code = <<~BASH
        if command -v hab >/dev/null 2>&1
        then
          echo "Habitat CLI already installed."
        else
          curl -o /tmp/install.sh 'https://raw.githubusercontent.com/habitat-sh/habitat/master/components/hab/install.sh'
          sudo -E bash /tmp/install.sh -v 1.5.29
        fi
      BASH
      expect(linux_install_cmd).to eq(expected_code)
    end
  end
end
