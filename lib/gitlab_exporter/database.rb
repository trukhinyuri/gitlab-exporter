module GitLab
  module Exporter
    # Database-related classes
    module Database
      autoload :Base,                 "gitlab_exporter/database/base"
      autoload :CiBuildsProber,       "gitlab_exporter/database/ci_builds"
      autoload :TuplesProber,         "gitlab_exporter/database/tuple_stats"
      autoload :RowCountProber,       "gitlab_exporter/database/row_count"
      autoload :BloatProber,          "gitlab_exporter/database/bloat"
      autoload :RemoteMirrorsProber,  "gitlab_exporter/database/remote_mirrors"
      autoload :PgSequencesProber,    "gitlab_exporter/database/pg_sequences"
      autoload :ZoektProber,          "gitlab_exporter/database/zoekt"
    end
  end
end
