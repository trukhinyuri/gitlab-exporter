require "spec_helper"
require "gitlab_monitor/database/row_count"

describe GitLab::Monitor::Database::RowCountCollector do
  let(:query)     { { project_1: { select: :projects, where: "id=1" } } }
  let(:collector) { described_class.new(connection_string: "host=localhost") }

  describe "#run" do
    before do
      stub_const("GitLab::Monitor::Database::RowCountCollector::QUERIES", query)
    end

    it "executes the query" do
      allow(collector).to receive(:execute).with(query[:project_1]).and_return(3)

      expect(collector.run).to eq(project_1: 3)
    end
  end

  describe "#construct_query" do
    it "accepts a table and where clause" do
      expect(collector.send(:construct_query, query[:project_1])).to eq "SELECT COUNT(*) FROM projects WHERE id=1;"
    end
  end
end
