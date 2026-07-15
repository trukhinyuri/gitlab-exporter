# gitlab-exporter — AI agent guidelines

gitlab-exporter is a Prometheus web exporter (a Ruby gem) that collects GitLab
production metrics via custom probes and exposes them over HTTP for a Prometheus
scraper. See `README.md` for the probe catalog.

## Project layout

- `lib/gitlab_exporter/` — probes and the exporter runtime
- `lib/gitlab_exporter/version.rb` — the gem version; bumping this on `master`
  triggers a release (see below)
- `bin/gitlab-exporter` — executable entry point
- `spec/` — RSpec tests (`-t integration` marks integration specs that need Redis/PG)

## Development commands

```sh
bundle install
bundle exec rspec spec           # unit tests
bundle exec rspec spec -t integration   # integration tests (needs Redis/Postgres)
bundle exec rubocop              # lint
```

## Commit messages

Follow the [GitLab commit message guidelines](https://docs.gitlab.com/development/contributing/merge_request_workflow/#commit-messages-guidelines).

- Subject: imperative mood, capitalized, no trailing period, ≤ 72 chars
  ("Add Zoekt probe", not "Added Zoekt probe").
- Body: explain *why*, wrap at 72 chars. Reference issues/MRs with full URLs,
  not short references (`#123`).

## Changelog trailer (required for user-facing changes)

Releases are cut by the `gem-release` CI component, which builds the release
notes from GitLab's changelog generator. That generator **only includes commits
that carry a `Changelog:` git trailer** — commits without one are dropped, which
is why a release can end up saying "No changes." and produce an empty changelog
in downstream projects (e.g. omnibus-gitlab's Renovate MRs).

Add the trailer as a **separate block at the end of the commit message**,
preceded by a blank line (the blank line is required for git to parse it as a
trailer; without it the changelog generator silently drops the commit):

```
Changelog: <type>
```

Valid types: `added`, `fixed`, `changed`, `deprecated`, `removed`, `security`,
`performance`, `other`.

**Include a trailer for:** new or changed probes/metrics, behavior changes,
bug fixes, dependency bumps that affect users, security fixes.

**Skip the trailer for:** test-only changes, documentation-only changes, CI/
tooling-only changes, and pure internal refactors with no user-visible effect.

Example:

```
Add remote mirror staleness metric

Exposes project_remote_mirror_last_successful_update_time_seconds so
operators can alert on mirrors that have stopped syncing.

Changelog: added
```

## Releasing

A release happens when `lib/gitlab_exporter/version.rb` changes on `master`.
The CI pipeline then generates the changelog from the `Changelog:` trailers
since the previous tag, creates the GitLab Release, and publishes the gem to
RubyGems. Keeping trailers accurate on every merged commit is what makes those
release notes meaningful.
