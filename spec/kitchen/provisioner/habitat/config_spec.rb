# frozen_string_literal: true

require "kitchen/provisioner/habitat"

RSpec.describe Kitchen::Provisioner::Habitat do
  include_context "habitat provisioner"

  # finalize_config! is the only place the package identity options are
  # normalised, and everything downstream -- the ident passed to
  # `hab pkg install`, the user.toml destination, the artifact glob -- assumes
  # it has already run.
  describe "#finalize_config!" do
    # Referencing `provisioner` runs finalize_config! through Kitchen::Instance.
    subject(:finalized) { provisioner.send(:config) }

    context "when package_name is a bare name" do
      let(:config) { { kitchen_root: "/kroot", package_name: "redis" } }

      it "leaves the name and the default origin alone" do
        expect(finalized[:package_name]).to eq("redis")
        expect(finalized[:package_origin]).to eq("core")
        expect(finalized[:package_version]).to be_nil
        expect(finalized[:package_release]).to be_nil
      end
    end

    context "when package_name is an origin/name pair" do
      let(:config) { { kitchen_root: "/kroot", package_name: "mycorp/wildfly" } }

      it "splits the origin out of the name" do
        expect(finalized[:package_origin]).to eq("mycorp")
        expect(finalized[:package_name]).to eq("wildfly")
        expect(finalized[:package_version]).to be_nil
        expect(finalized[:package_release]).to be_nil
      end
    end

    context "when package_name is a fully qualified identifier" do
      let(:config) do
        { kitchen_root: "/kroot", package_name: "core/redis/4.0.14/20240106065001" }
      end

      it "splits all four parts out" do
        expect(finalized[:package_origin]).to eq("core")
        expect(finalized[:package_name]).to eq("redis")
        expect(finalized[:package_version]).to eq("4.0.14")
        expect(finalized[:package_release]).to eq("20240106065001")
      end

      it "rebuilds the same identifier" do
        expect(provisioner.send(:package_ident)).to eq("core/redis/4.0.14/20240106065001")
      end
    end

    context "when package_name is nil" do
      let(:config) { { kitchen_root: "/kroot" } }

      it "does not try to split it" do
        expect(finalized[:package_name]).to be_nil
        expect(finalized[:package_origin]).to eq("core")
      end
    end

    context "when an artifact_name is given" do
      let(:config) do
        {
          kitchen_root: "/kroot",
          package_origin: "ignored",
          package_name: "ignored",
          artifact_name: "mycorp-wildfly-26.1.1-20240115194501-x86_64-linux.hart",
        }
      end

      it "takes the package identity from the filename, overriding what was configured" do
        expect(finalized[:package_origin]).to eq("mycorp")
        expect(finalized[:package_name]).to eq("wildfly")
        expect(finalized[:package_version]).to eq("26.1.1")
        expect(finalized[:package_release]).to eq("20240115194501")
      end
    end

    context "when both a service and a supervisor artifact are given" do
      let(:config) do
        {
          kitchen_root: "/kroot",
          artifact_name: "mycorp-wildfly-26.1.1-20240115194501-x86_64-linux.hart",
          hab_sup_artifact_name: "core-hab-sup-1.6.652-20240115194501-x86_64-linux.hart",
        }
      end

      it "keeps the two identities separate" do
        expect(finalized[:package_name]).to eq("wildfly")
        expect(finalized[:hab_sup_name]).to eq("hab-sup")
        expect(finalized[:hab_sup_version]).to eq("1.6.652")
      end
    end
  end

  describe "#package_ident" do
    let(:config) { { kitchen_root: "/kroot" } }

    it "emits origin/name when no version or release is set" do
      config[:package_name] = "redis"

      expect(provisioner.send(:package_ident)).to eq("core/redis")
    end

    it "emits origin/name/version when only a version is set" do
      config[:package_name] = "redis"
      config[:package_version] = "4.0.14"

      expect(provisioner.send(:package_ident)).to eq("core/redis/4.0.14")
    end
  end

  describe "#artifact_name_to_package_ident_regex" do
    let(:config) { { kitchen_root: "/kroot" } }

    it "captures every part of a hart filename" do
      match = provisioner.send(:artifact_name_to_package_ident_regex)
        .match("core-redis-4.0.14-20240106065001-x86_64-linux.hart")

      expect(match["origin"]).to eq("core")
      expect(match["name"]).to eq("redis")
      expect(match["version"]).to eq("4.0.14")
      expect(match["release"]).to eq("20240106065001")
      expect(match["target"]).to eq("x86_64-linux")
    end

    it "handles a hyphenated package name" do
      match = provisioner.send(:artifact_name_to_package_ident_regex)
        .match("core-hab-sup-1.6.652-20240115194501-x86_64-linux.hart")

      expect(match["name"]).to eq("hab-sup")
      expect(match["version"]).to eq("1.6.652")
    end

    it "does not match a filename that is not a hart" do
      expect(provisioner.send(:artifact_name_to_package_ident_regex)
        .match("core-redis-4.0.14-20240106065001-x86_64-linux.tar.gz")).to be_nil
    end
  end
end
