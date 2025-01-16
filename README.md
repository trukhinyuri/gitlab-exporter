## Introduction

gitlab-exporter is a [Prometheus Web exporter] that does the following:

1. Collects GitLab production metrics via custom probes defined in a [YAML
   configuration file](config/gitlab-exporter.yml.example).
2. Custom probes gather measurements in the form of key/value pairs.
3. For each probe, gitlab-exporter creates an HTTP endpoint `/<probe_name>`
   (by default on port 9168) that delivers these metrics to a Prometheus scraper.

A central Prometheus process is configured to poll exporters at a specified
frequency.

### Supported Probes

Below is a list of probes added by this exporter, and their corresponding
metrics.

1. Database
    * [Per-table tuple stats](lib/gitlab_exporter/database/tuple_stats.rb) --
      `gitlab_database_stat_table_*`
   * [Per-sequence stats](lib/gitlab_exporter/database/pg_sequences.rb) --
     `gitlab_pg_sequences_min_value`, `gitlab_pg_sequences_max_value`, `gitlab_pg_sequences_current_value`
    * [Row count queries](lib/gitlab_exporter/database/row_count.rb) --
      `gitlab_database_rows`
    * [CI builds](lib/gitlab_exporter/database/ci_builds.rb) --
      `ci_pending_builds`, `ci_created_builds`, `ci_stale_builds`,
      `ci_running_builds`
    * [Bloat](lib/gitlab_exporter/database/bloat.rb) --
      `gitlab_database_bloat_$type_$key` with type `btree` (index bloat) or `table`
      (table bloat) and keys `bloat_ratio bloat_size extra_size real_size` (see below)
    * [Remote mirrors](lib/gitlab_exporter/database/remote_mirrors.rb) --
      `project_remote_mirror_last_successful_update_time_seconds`, `project_remote_mirror_last_update_time_seconds`
1. Git
    * [git pull/push timings](lib/gitlab_exporter/git.rb) --
      `git_pull_time_milliseconds`, `git_push_time_milliseconds`
    * git processes stats (see Process below)
1. [Sidekiq](lib/gitlab_exporter/sidekiq.rb)
	* Stats (probe_stats)
	  * `sidekiq_jobs_processed_total`
	  * `sidekiq_jobs_failed_total`
	  * `sidekiq_jobs_enqueued_size`
	  * `sidekiq_jobs_scheduled_size`
	  * `sidekiq_jobs_retry_size`
	  * `sidekiq_jobs_dead_size`
	  * `sidekiq_default_queue_latency_seconds`
	  * `sidekiq_processes_size`
	  * `sidekiq_workers_size`
	* Queues (probe_queues)
	  * `sidekiq_queue_size`
	  * `sidekiq_queue_paused`
	  * `sidekiq_queue_latency_seconds`
	* Jobs (probe_jobs_limit)
	  * `sidekiq_enqueued_jobs`
  * Workers (probe_workers)
	  * `sidekiq_running_jobs`
  * Retries (probe_retries)
	  * `sidekiq_to_be_retried_jobs`
  * Future Sets (probe_future_sets)
    * `sidekiq_schedule_set_processing_delay_seconds`
    * `sidekiq_schedule_set_backlog_count`
    * `sidekiq_retry_set_processing_delay_seconds`
    * `sidekiq_retry_set_backlog_count`
1. [Elasticsearch](lib/gitlab_exporter/elasticsearch.rb)
  * [Migrations](https://docs.gitlab.com/ee/integration/elasticsearch.html#advanced-search-migrations) -- `elasticsearch_migrations_state`

### Setup with GitLab Development Kit

gitlab-exporter can be setup with the [GitLab Development Kit] for development.
When using the gitlab-exporter CLI, you'll need to set the `--db-conn` flag to
connect to the PostgreSQL instance in your GDK folder. For example:

```
bin/gitlab-exporter row-counts --db-conn="dbname=gitlabhq_development host=/Users/<user>/gitlab-development-kit/postgresql"
```

### Running gitlab-exporter as a Web exporter

When serving the pages on `localhost`, you'll need to edit the YAML
configuration file. An example can be found under
[`config/gitlab-exporter.yml.example`](config/gitlab-exporter.yml.example). For
each probe that has to connect to the database, set the `connection_string` to
`dbname=gitlabhq_development
host=/Users/<user>/gitlab-development-kit/postgresql`

Once you have this configured, you can then run:

```
bin/gitlab-exporter web -c config/gitlab-exporter.yml
```

Once running, you can point your browser or curl to the following URLs:

* http://localhost:9168/database
* http://localhost:9168/git_process
* http://localhost:9168/process
* http://localhost:9168/sidekiq
* http://localhost:9168/metrics (to get all of the above combined)

If it is undesirable to have secrets (e.g. Redis password or PostgreSQL credentials) in the config file,
then you can specify an external command (with the `--extra-config-command <command>` flag) that outputs
such credentials in a YAML form (same structure as the config file) and it will be merged with the file configuration.

For example:

```
$ vault kv get -format=yaml secrets/gitlab/gitlab-exporter
probes:
  sidekiq:
    opts:
      redis_url: redis://hunter1@localhost:9765
  database:
    opts:
      connection_string: postgres://db-admin:hunter1@localhost:6543/main-db

$ bin/gitlab-exporter web -c config/gitlab-exporter.yml --extra-config-command "vault kv get -format=yaml secrets/gitlab/gitlab-exporter"
```

### Database Bloat Metrics

Database bloat is measured for indexes (`btree`) and/or tables
(`table`). Returned metrics contain:

* `bloat_ratio`: estimated ratio of the real size used by bloat_size.
* `bloat_size`: estimated size of the bloat without the extra space kept for the fillfactor.
* `extra_size`: estimated extra size not used/needed by the index. This extra size is composed by the fillfactor, bloat and alignment padding spaces.
* `real_size`: real size of the index

Also see the [original documentation](https://github.com/ioguix/pgsql-bloat-estimation/blob/master/README.md).

Note that all metrics returned are estimates without an upper bound for
the error.

## Contributing

gitlab-exporter is an open source project and we are very happy to accept community contributions. Please refer to [CONTRIBUTING.md](/CONTRIBUTING.md) for details.

[Prometheus Web exporter]: https://prometheus.io/docs/instrumenting/exporters/
[GitLab Development Kit]: https://gitlab.com/gitlab-org/gitlab-development-kit
