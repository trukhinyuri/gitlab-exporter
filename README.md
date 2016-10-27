## Introduction

gitlab-monitor is a [Prometheus Web exporter] that does the following:

1. Collects GitLab production metrics via custom probes defined in a YAML file.
2. Custom probes gather measurements in the form of key/value pairs.
3. For each probe, gitlab-monitor creates an HTTP endpoint `/<probe_name>`
   (by default on port 4567) that delivers these metrics to a Prometheus scraper.

A central Prometheus process is configured to poll exporters at a specified
frequency.

### Supported Probes

1. Database
    * Dead tuples
    * Slow queries
    * Blocked queries
    * Vacuum queries
1. Git
    * git pull/push timings
1. Process
    * Age
    * Memory usage
1. Sidekiq

[Prometheus Web exporter]: https://prometheus.io/docs/instrumenting/exporters/
