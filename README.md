## Introduction

gitlab-monitor is a [Prometheus Web exporter] that does the following:

1. Collects GitLab production metrics via custom probes defined in a [YAML
   configuration file](config/gitlab-monitor.yml.example).
2. Custom probes gather measurements in the form of key/value pairs.
3. For each probe, gitlab-monitor creates an HTTP endpoint `/<probe_name>`
   (by default on port 9168) that delivers these metrics to a Prometheus scraper.

A central Prometheus process is configured to poll exporters at a specified
frequency.

### Supported Probes

Below is a list of probes added by this exporter, and their corresponding
metrics.

1. Database
    * [Per-table tuple stats](lib/gitlab_monitor/database/tuple_stats.rb) --
      `pg_stat_table_*`
    * [Slow queries](lib/gitlab_monitor/database/slow_queries.rb) --
      `pg_slow_queries_total`
    * [Stuck queries in idle in transaction](lib/gitlab_monitor/database/stuck_idle_in_transactions.rb) --
      `pg_stuck_idle_in_transactions_total`
    * [Blocked queries](lib/gitlab_monitor/database/blocked_queries.rb) --
      `pg_blocked_queries_total`
    * [Vacuum queries](lib/gitlab_monitor/database/vacuum_queries.rb) --
      `pg_vacuum_count`, `pg_vacuum_age_in_seconds`, `pg_vacuum_analyze_count`,
      `pg_vacuum_analyze_age_in_seconds`
    * [Row count queries](lib/gitlab_monitor/database/row_count.rb) --
      `db_rows_count`
    * [CI builds](lib/gitlab_monitor/database/ci_builds.rb) --
      `ci_pending_builds`, `ci_created_builds`, `ci_stale_builds`,
      `ci_running_builds`
1. Git
    * [git pull/push timings](lib/gitlab_monitor/git.rb) --
      `git_pull_time_milliseconds`, `git_push_time_milliseconds`
    * git processes stats (see Process below)
1. [Process](lib/gitlab_monitor/process.rb)
    * Age -- `process_age_seconds`
    * Count -- `process_count`
    * Memory usage -- `process_memory_bytes`
1. [Sidekiq](lib/gitlab_monitor/sidekiq.rb) -- `sidekiq_queue_size`,
   `sidekiq_queue_latency`, `sidekiq_enqueued_jobs_count`,
   `sidekiq_running_jobs_count`, `sidekiq_jobs_to_be_retried_count`

### Setup with GitLab Development Kit

gitlab-monitor can be setup with the [GitLab Development Kit] for development.
When using the gitlab-monitor CLI, you'll need to set the `--db-conn` flag to
connect to the PostgreSQL instance in your GDK folder. For example:

```
bin/gitlab-mon row-counts --db-conn="dbname=gitlabhq_development host=/Users/<user>/gitlab-development-kit/postgresql"
```

### Running gitlab-monitor as a Web exporter

When serving the pages on `localhost`, you'll need to edit the YAML
configuration file. An example can be found under
[`config/gitlab-monitor.yml.example`](config/gitlab-monitor.yml.example). For
each probe that has to connect to the database, set the `connection_string` to
`dbname=gitlabhq_development
host=/Users/<user>/gitlab-development-kit/postgresql`

Once you have this configured, you can then run:

```
bin/gitlab-mon web -c config/gitlab-monitor.yml
```

Once running, you can point your browser or curl to the following URLs:

* http://localhost:9168/database
* http://localhost:9168/git
* http://localhost:9168/process
* http://localhost:9168/sidekiq

[Prometheus Web exporter]: https://prometheus.io/docs/instrumenting/exporters/
[GitLab Development Kit]: https://gitlab.com/gitlab-org/gitlab-development-kit
