## Introduction

gitlab-monitor is a [Prometheus Web exporter] that does the following:

1. Collects GitLab production metrics via custom probes defined in a YAML file
  (config format is explained in [config/gitlab-monitor.yml.example]).
2. Custom probes gather measurements in the form of key/value pairs.
3. For each probe, gitlab-monitor creates an HTTP endpoint `/<probe_name>`
   (by default on port 9168) that delivers these metrics to a Prometheus scraper.

A central Prometheus process is configured to poll exporters at a specified
frequency.

### Supported Probes

1. Database
    * Per-table tuple stats
    * Slow queries
    * Blocked queries
    * Vacuum queries
    * Row count queries
    * CI builds
1. Git
    * git pull/push timings
    * git processes stats (see Process below)
1. Process
    * Age
    * Count
    * Memory usage
1. Sidekiq

### Setup with GitLab Development Kit

gitlab-monitor can be setup with the [GitLab Development Kit] for development.
When using the CLI, you'll need to set the --db-conn flag to connect to the PG
instance in your GDK folder. Like:

`bin/gitlab-mon row-counts --db-conn="dbname=gitlabhq_development host=/Users/<user>/gitlab-development-kit/postgresql"`

When serving the pages on localhost, you'll need to edit the config yaml. An
example can be found under `config/gitlab-monitor.yml.example`. For each probe
which has to connect to the database, set the connection_string to:
`dbname=gitlabhq_development host=/Users/<user>/gitlab-development-kit/postgresq`

[Prometheus Web exporter]: https://prometheus.io/docs/instrumenting/exporters/
[GitLab Development Kit]: https://gitlab.com/gitlab-org/gitlab-development-kit
[config/gitlab-monitor.yml.example]: https://gitlab.com/gitlab-org/gitlab-monitor/blob/master/config/gitlab-monitor.yml.example
