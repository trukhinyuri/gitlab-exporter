require "spec_helper"
require "gitlab_exporter/sidekiq"

describe GitLab::Exporter::SidekiqProber do
  let(:probe_list) { %w[probe_stats probe_queues probe_future_sets probe_jobs_limit probe_workers probe_retries] }
  let(:opt) { {} }
  let(:probe) { described_class.new(**opt) }

  before do
    # stub connection as we want check if the probe methods are called
    # with the right namespace argument
    allow(probe).to receive(:connected?).and_return(true)
  end

  context "when no namespace options are defined" do
    it "defaults to probing non-namespaced keys only" do
      probe_list.each do |probe_type|
        expect(probe).not_to receive("_#{probe_type}".to_sym).with(false)
        expect(probe).to receive("_#{probe_type}".to_sym).with(no_args)

        probe.send(probe_type)
      end
    end
  end

  context "when probing both namespaces" do
    let(:opt) { { probe_non_namespaced: true, probe_namespaced: true } }

    it "probes both namespaces" do
      probe_list.each do |probe_type|
        expect(probe).to receive("_#{probe_type}".to_sym).with(false)
        expect(probe).to receive("_#{probe_type}".to_sym).with(no_args)

        probe.send(probe_type)
      end
    end
  end

  context "when probing non-namespaced only" do
    let(:opt) { { probe_non_namespaced: true } }

    it "probes non-namespaced only" do
      probe_list.each do |probe_type|
        expect(probe).to receive("_#{probe_type}".to_sym).with(false)
        expect(probe).not_to receive("_#{probe_type}".to_sym).with(no_args)

        probe.send(probe_type)
      end
    end
  end

  context "when probing namespace only" do
    let(:opt) { { probe_namespaced: true } }

    it "probes namespaced only" do
      probe_list.each do |probe_type|
        expect(probe).not_to receive("_#{probe_type}".to_sym).with(false)
        expect(probe).to receive("_#{probe_type}".to_sym).with(no_args)

        probe.send(probe_type)
      end
    end
  end
end
