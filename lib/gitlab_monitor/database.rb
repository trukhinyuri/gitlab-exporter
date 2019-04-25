module GitLab
  module Monitor
    # Database-related classes
    module Database
      autoload :Base,                 "gitlab_monitor/database/base"
      autoload :CiBuildsProber,       "gitlab_monitor/database/ci_builds"
      autoload :TuplesProber,         "gitlab_monitor/database/tuple_stats"
      autoload :RowCountProber,       "gitlab_monitor/database/row_count"
      autoload :BloatProber,          "gitlab_monitor/database/bloat"
      autoload :RemoteMirrorsProber,  "gitlab_monitor/database/remote_mirrors"
    end
  end
end
