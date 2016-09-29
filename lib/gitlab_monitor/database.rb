module GitLab
  module Monitor
    # Database-related classes
    module Database
      autoload :Base,                 "gitlab_monitor/database/base"
      autoload :BlockedQueriesProber, "gitlab_monitor/database/blocked_queries"
      autoload :SlowQueriesProber,    "gitlab_monitor/database/slow_queries"
      autoload :DeadTuplesProber,     "gitlab_monitor/database/dead_tuples"
    end
  end
end
