require "spec_helper"
require "gitlab_exporter/database/row_count"

describe GitLab::Exporter::Database::RowCountCollector do
  let(:query) {
    { project_1: { select: :projects, where: "id=1" },
      project_2: { select: :projects, where: "id=2" },
      project_3: { select: :projects, fields: { is_public: { definition: "visibility_level == 20" } } } }
  }
  let(:collector) { described_class.new(connection_string: "host=localhost") }

  describe "#run" do
    before do
      stub_const("GitLab::Exporter::Database::RowCountCollector::QUERIES", query)

      allow(collector).to receive(:execute).with("SELECT COUNT(*) FROM projects WHERE id=1;").and_return(false)
      allow(collector).to receive(:execute).with("SELECT COUNT(*) FROM projects WHERE id=2;").and_return(
        [{ "count" => 6 }]
      )
      allow(collector).to receive(:execute).with(
        "SELECT COUNT(*), (visibility_level == 20) AS is_public FROM projects GROUP BY is_public;"
      ).and_return(
        [{ "count" => 3, "is_public" => true }, { "count" => 6, "is_public" => false }]
      )
    end

    it "executes all the queries" do
      expect(collector.run).to eq(
        project_1: [{ count: 0, labels: {} }],
        project_2: [{ count: 6, labels: {} }],
        project_3: [{ count: 3, labels: { is_public: true  } },
                    { count: 6, labels: { is_public: false } }]
      )
    end

    context "when selected_queries is passed" do
      let(:collector) { described_class.new(connection_string: "host=localhost", selected_queries: ["project_2"]) }

      it "executes the selected queries" do
        expect(collector.run).to eq(project_2: [{ count: 6, labels: {} }])
      end
    end
  end

  describe "#construct_query" do
    it "accepts a table and where clause" do
      expect(collector.send(:construct_query, query[:project_1])).to eq "SELECT COUNT(*) FROM projects WHERE id=1;"
    end

    it "accepts a table and group (field) clause" do
      expect(collector.send(:construct_query, query[:project_3])).to eq \
        "SELECT COUNT(*), (visibility_level == 20) AS is_public FROM projects GROUP BY is_public;"
    end
  end
end
