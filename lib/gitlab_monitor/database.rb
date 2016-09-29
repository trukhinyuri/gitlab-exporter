module GitLab
  module Monitor
    # Database-related classes
    module Database
      autoload :Base,                 "gitlab_monitor/database/base"
      autoload :DeadTuplesProber,     "gitlab_monitor/database/dead_tuples"
    end
  end
end
