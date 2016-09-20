module GitLab
  # GitLab Monitoring
  module Monitor
    autoload :CLI,               "gitlab_monitor/cli"
    autoload :TimeTracker,       "gitlab_monitor/util"
    autoload :PrometheusMetrics, "gitlab_monitor/prometheus"
    autoload :Git,               "gitlab_monitor/git"
    autoload :GitProber,         "gitlab_monitor/git"
    autoload :DatabaseDeadTuplesCollector, "gitlab_monitor/database_dead_tuples"
    autoload :DatabaseDeadTuplesProber,    "gitlab_monitor/database_dead_tuples"
  end
end
