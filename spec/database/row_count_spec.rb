require "spec_helper"
require "gitlab_monitor/database/row_count"

describe GitLab::Monitor::Database::RowCountCollector do
  let(:query) {
    { project_1: { select: :projects, where: "id=1" },
      project_2: { select: :projects, where: "id=2" } }
  }
  let(:collector) { described_class.new(connection_string: "host=localhost") }

  describe "#run" do
    before do
      stub_const("GitLab::Monitor::Database::RowCountCollector::QUERIES", query)

      allow(collector).to receive(:count_from_query_hash).with(query[:project_1]).and_return(3)
      allow(collector).to receive(:count_from_query_hash).with(query[:project_2]).and_return(6)
    end

    it "executes all the queries" do
      expect(collector.run).to eq(project_1: 3, project_2: 6)
    end

    context "when selected_queries is passed" do
      let(:collector) { described_class.new(connection_string: "host=localhost", selected_queries: ["project_2"]) }

      it "executes the selected queries" do
        expect(collector.run).to eq(project_2: 6)
      end
    end
  end

  describe "#construct_query" do
    it "accepts a table and where clause" do
      expect(collector.send(:construct_query, query[:project_1])).to eq "SELECT COUNT(*) FROM projects WHERE id=1;"
    end
  end
end
