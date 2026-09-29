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
    * [CI builds](lib/gitlab_exporter/database/ci_builds.rb) (**deprecated**) --
      `ci_pending_builds`, `ci_created_builds`, `ci_stale_builds`,
      `ci_running_builds`, `ci_unarchived_traces`
      (see [Deprecated: CI builds metrics](#deprecated-ci-builds-metrics))
    * [Bloat](lib/gitlab_exporter/database/bloat.rb) --
      `gitlab_database_bloat_$type_$key` with type `btree` (index bloat) or `table`
      (table bloat) and keys `bloat_ratio bloat_size extra_size real_size` (see below)
    * [Remote mirrors](lib/gitlab_exporter/database/remote_mirrors.rb) --
      `project_remote_mirror_last_successful_update_time_seconds`, `project_remote_mirror_last_update_time_seconds`
    * [Geo node status](lib/gitlab_exporter/database/geo_node_status.rb) -- Geo metrics from
      `geo_node_statuses`, emitted as `geo_<status_field>` gauges with trailing `_count` and
      `_total` suffixes removed and labeled by `geo_node_id` and `geo_node_name`. Enable the
      `geo_node_status` probe in the `database` endpoint configuration.
    * [Zoekt](lib/gitlab_exporter/database/zoekt.rb) --
      `search_zoekt_task_processing_queue_size`
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

### Deprecated: CI builds metrics

The [CI builds probe](lib/gitlab_exporter/database/ci_builds.rb) is deprecated and
will be removed in a future major version. It collects its metrics by querying
`p_ci_builds` directly, which puts avoidable load on tables that job scheduling
already loads heavily, and it has had almost no maintenance since 2021. GitLab
Rails and GitLab Runner instrument most of the same information by counting
events as they happen; GitLab.com stopped using this probe for CI state years
ago.

The probe prints a deprecation notice on every run, and each of its metrics
carries `(deprecated, ...)` in its `# HELP` line, so the warning reaches
Prometheus and Grafana and not only the exporter's log.

Replacements, where one exists:

| Deprecated metric | Replacement |
| --- | --- |
| `ci_pending_builds` | `gitlab_ci_current_queue_size` (Rails, gauge, by `runner_type`) |
| `ci_running_builds` | `gitlab_runner_jobs` (Runner, gauge, by `runner`, `state`, `stage`) |
| `ci_created_builds` | None. A `created` build is not queued yet, so nothing counts it. |
| `ci_stale_builds` | None. The nearest signal is `gitlab_ci_queue_operations_total{operation="build_status_stale"}` (Rails, counter), which counts stale rows met while queueing rather than how many are stale now. |
| `ci_unarchived_traces` | None. |

The replacements are not a like-for-like relabel: the Rails queue metrics are
keyed by `runner_type` and the Runner metrics by runner, so neither carries the
`namespace` label this probe reports. Queue health is better served by the Rails
metrics that have no exporter equivalent at all -- `job_queue_duration_seconds`
(how long jobs wait), `job_register_attempts_total` and
`job_register_attempts_failed_total`, and `gitlab_ci_queue_operations_total`.
Those four are always instrumented.

**`gitlab_ci_current_queue_size`, and every other `gitlab_ci_queue_*` metric, is
behind the `gitlab_ci_builds_queuing_metrics` ops feature flag, which is disabled
by default.** Enable it before pointing a dashboard at them, or the replacement
panels stay empty:

```ruby
Feature.enable(:gitlab_ci_builds_queuing_metrics)
```

Metric definitions live in
[`lib/gitlab/ci/queue/metrics.rb`](https://gitlab.com/gitlab-org/gitlab/-/blob/master/lib/gitlab/ci/queue/metrics.rb)
(Rails) and
[`commands/builds_helper.go`](https://gitlab.com/gitlab-org/gitlab-runner/-/blob/main/commands/builds_helper.go)
(Runner). See
[GitLab Prometheus metrics](https://docs.gitlab.com/administration/monitoring/prometheus/gitlab_metrics/)
for enabling the Rails exporter, and
[Monitoring runners](https://docs.gitlab.com/runner/monitoring/) for the
Runner's.

## Contributing

gitlab-exporter is an open source project and we are very happy to accept community contributions. Please refer to [CONTRIBUTING.md](/CONTRIBUTING.md) for details.

[Prometheus Web exporter]: https://prometheus.io/docs/instrumenting/exporters/
[GitLab Development Kit]: https://gitlab.com/gitlab-org/gitlab-development-kit
