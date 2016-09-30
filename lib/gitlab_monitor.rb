module GitLab
  # GitLab Monitoring
  module Monitor
    autoload :CLI,               "gitlab_monitor/cli"
    autoload :TimeTracker,       "gitlab_monitor/util"
    autoload :Utils,             "gitlab_monitor/util"
    autoload :PrometheusMetrics, "gitlab_monitor/prometheus"
    autoload :Git,               "gitlab_monitor/git"
    autoload :GitProber,         "gitlab_monitor/git"
    autoload :Database,          "gitlab_monitor/database"
    autoload :WebExporter,       "gitlab_monitor/web_exporter"
  end
end
