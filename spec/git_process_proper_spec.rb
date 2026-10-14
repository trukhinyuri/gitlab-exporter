require "spec_helper"
require "gitlab_exporter"

# rubocop:disable Layout/LineLength
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

    it "handles invalid UTF-8 and non-ASCII byte sequences in command line arguments without raising ArgumentError" do
      invalid_utf8_cmdline = (+"git\u0000--git-dir=/tmp/\xFF\xFE\u0000commit\u0000-m\u0000fix: \xFF\xFEmessage").force_encoding(Encoding::UTF_8)
      expect(described_class.extract_subcommand(invalid_utf8_cmdline)).to eq("commit")

      us_ascii_non_ascii_cmdline = (+"git\x00--git-dir=/tmp/repo\x00commit\x00-m\x00\xD0\xBF\xD1\x80\xD0\xBE\xD0\xB2\xD0\xB5\xD1\x80\xD0\xBA\xD0\xB0").force_encoding(Encoding::US_ASCII)
      expect(described_class.extract_subcommand(us_ascii_non_ascii_cmdline)).to eq("commit")
    end
  end
end
