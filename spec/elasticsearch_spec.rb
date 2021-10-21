require "spec_helper"
require "gitlab_exporter/elasticsearch"

describe GitLab::Exporter::ElasticsearchProber do
  subject(:prober) { GitLab::Exporter::Prober.new(**options) }
  let(:options) do
    {
      elasticsearch: {
        class_name: described_class.to_s,
        methods: %i[probe_migrations],
        opts: {
          url: "http://elasticsearch"
        }
      }
    }
  end

  let(:connection) { instance_double(Faraday::Connection) }

  describe "probe_migrations" do
    let(:response) { double(:response, body: results, status: 200) }
    let(:metric_name) { "elasticsearch_migrations_info" }

    let(:results) do
      <<-RESULTS
      {
        "took": 5,
        "timed_out": false,
        "_shards": {
          "total": 1,
          "successful": 1,
          "skipped": 0,
          "failed": 0
        },
        "hits": {
          "total": {
            "value": 1,
            "relation": "eq"
          },
          "max_score": 1,
          "hits": [#{document.to_json}]
        }
      }
      RESULTS
    end

    let(:document) do
      { "_id" => "123", "_source" => migration }
    end

    let(:migration) do
      {
        "started_at" => "",
        "completed_at" => "",
        "completed" => false,
        "state" => {}
      }.tap do |m|
        case migration_state
        when "running"
          m["started_at"] = "2021-09-23T11:47:48,890Z"
        when "completed"
          m["started_at"] = "2021-09-23T11:47:48,890Z"
          m["completed_at"] = "2021-09-24T11:47:48,890Z"
          m["completed"] = true
        when "halted"
          m["started_at"] = "2021-09-23T11:47:48,890Z"
          m["state"]["halted"] = true
        end
      end
    end

    let(:output) do
      prober.probe_all
      StringIO.new.tap do |s|
        prober.write_to(s)
      end
    end

    before do
      allow_any_instance_of(described_class).to receive(:elastic_probe).and_yield(connection)
    end

    describe "when an Exception is raised" do
      before do
        allow(connection).to receive(:get).with("/gitlab-*-migrations/_search").and_raise("boom")
      end

      it "does NOT raise an error" do
        expect { output }.to_not raise_error
      end

      it "does NOT export any metrics" do
        expect(output.string).not_to match(/#{metric_name}/)
      end
    end

    describe "when elasticsearch is reachable" do
      let(:expected_output) { /#{metric_name}{state="#{migration_state}",name="123"} 1 \d+/ }
      before do
        allow(connection).to receive(:get).with("/gitlab-*-migrations/_search").and_return response
      end

      context "when there is a pending migration" do
        let(:migration_state) { "pending" }
        it "exports state correctly" do
          expect(output.string).to match(expected_output)
        end
      end

      context "when there is a running migration" do
        let(:migration_state) { "running" }
        it "exports state correctly" do
          expect(output.string).to match(expected_output)
        end
      end

      context "when there is a halted migration" do
        let(:migration_state) { "halted" }
        it "exports state correctly" do
          expect(output.string).to match(expected_output)
        end
      end

      context "when there is a completed migration" do
        let(:migration_state) { "completed" }
        it "exports state correctly" do
          expect(output.string).to match(expected_output)
        end
      end
    end
  end
end
