module GitLab
  module Monitor
    autoload :TimeTracker, "gitlab_monitor/util"
    autoload :PrometheusMetrics,  "gitlab_monitor/prometheus"
  end
end
