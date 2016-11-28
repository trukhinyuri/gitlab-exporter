module GitLab
  module Monitor
    # Database-related classes
    module Database
      autoload :Base,                 "gitlab_monitor/database/base"
      autoload :BlockedQueriesProber, "gitlab_monitor/database/blocked_queries"
      autoload :CiBuildsProber,       "gitlab_monitor/database/ci_builds"
      autoload :SlowQueriesProber,    "gitlab_monitor/database/slow_queries"
      autoload :DeadTuplesProber,     "gitlab_monitor/database/dead_tuples"
      autoload :VacuumQueriesProber,  "gitlab_monitor/database/vacuum_queries"
      autoload :RowCountProber,       "gitlab_monitor/database/row_count"
    end
  end
end
