module GitLab
  # GitLab Monitoring
  module Exporter
    autoload :CLI,               "gitlab_exporter/cli"
    autoload :TimeTracker,       "gitlab_exporter/util"
    autoload :Utils,             "gitlab_exporter/util"
    autoload :PrometheusMetrics, "gitlab_exporter/prometheus"
    autoload :Utils,             "gitlab_exporter/util"
    autoload :Git,               "gitlab_exporter/git"
    autoload :GitProber,         "gitlab_exporter/git"
    autoload :GitProcessProber,  "gitlab_exporter/git"
    autoload :Database,          "gitlab_exporter/database"
    autoload :ProcessProber,     "gitlab_exporter/process"
    autoload :WebExporter,       "gitlab_exporter/web_exporter"
    autoload :Prober,            "gitlab_exporter/prober"
    autoload :SidekiqProber,     "gitlab_exporter/sidekiq"
  end
end
