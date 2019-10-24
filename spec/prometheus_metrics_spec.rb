require "spec_helper"

describe GitLab::Exporter::PrometheusMetrics do
  it "supports simple metrics" do
    expect(subject.add("mymetric", 1.1).to_s).to match(/mymetric 1.1 \d*$/)
  end

  it "supports metrics with one label" do
    expect(subject.add("mymetric", 1.2, mylabel: "x").to_s).to match(/mymetric{mylabel="x"} 1.2 \d*$/)
  end

  it "supports metrics with many labels" do
    expect(subject.add("mymetric", 1.3, mylabel: "x", myotherlabel: "y").to_s).to match(
      /mymetric{mylabel="x",myotherlabel="y"} 1.3 \d*$/
    )
  end

  it "fails to add a non-numeric metric value" do
    expect {
      subject.add("mymetric", "1.4", mylabel: "x", myotherlabel: "y").to_s
    }.to raise_error(RuntimeError)
    expect {
      subject.add("mymetric", "invalid", mylabel: "x", myotherlabel: "y").to_s
    }.to raise_error(RuntimeError)
  end
end
