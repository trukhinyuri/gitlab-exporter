require "spec_helper"
require "gitlab_exporter"

# rubocop:disable Metrics/LineLength
describe GitLab::Exporter::GitProcessProber do
  describe ".extract_subcommand" do
    it "extract git subcommand" do
      command_subcommands = {
        "git upload-pack --stateless-rpc --advertise-refs /repositories/Hey/project.git" => "upload-pack",
        "git --git-dir=/repositories/null/gitlab-ce.git fetch upstream --tags" => "fetch",
        "git --shallow-file  pack-objects --revs --thin --stdout --shallow --delta-base-offset" => "pack-objects",
        "git /repositories/some/thing.git pack-objects" => "pack-objects",
        "git --git-dir=/repositories/Fact/arti.git cat-file blob 13b39ff4503badb8182b901c471039d6ab6ab96b" => "cat-file",
        "git --git-dir /repositories/Fact/arti.git cat-file blob 13b39ff4503badb8182b901c471039d6ab6ab96b" => "cat-file",
        "git --git-dir=/repositories/an/web.git gc" => "gc",
        "git --git-dir=/repositories/an/web.git  gc" => "gc",
        "git --git-dir /repositories/an/web.git gc" => "gc",
        "git --git-dir /repositories/an/web.git" => nil
      }

      command_subcommands.each do |command, subcommand|
        cmdline = command.tr(" ", "\u0000")
        expect(described_class.extract_subcommand(cmdline)).to eq(subcommand)
      end
    end
  end
end
