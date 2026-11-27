# Astronomy Shop

The [OpenTelemetry Demo](https://github.com/open-telemetry/opentelemetry-demo) shop with
Pyroscope profiling, running on Kubernetes and observed with the Grafana stack
(Prometheus/Mimir, Loki, Tempo, Pyroscope).

## Deploying

Every push to `main` deploys (workflow **Deploy**):

1. `deploy/build.sh` builds the services whose `src/<service>/` differs from branch
   `baseline` (the commit the base images were built from) and pins them by digest.
2. `deploy/deploy.sh` installs the Helm chart (`deploy/chart.env`) with
   `deploy/values.yaml`, `deploy/values.cio-demo.yaml` and the images.
3. `deploy/grafana-sync.sh` loads `observability/dashboards` and `observability/alerts`
   into the shop's Grafana folder.

4. `deploy/smoke-test.sh` checks that the shop answers at its public address.

Changes reach `main` through pull requests: one approval and the checks `guard` and
`ci`, plus an automatic Copilot review (`.github/copilot-instructions.md`).

## CI

Workflow **CI** (`.github/workflows/ci.yml`, checks in `deploy/ci.sh`) on every pull
request to `main`; job `ci` is the required check:

| Job | What |
|---|---|
| lint | ShellCheck, actionlint, yamllint, hadolint, Ruff, markdownlint, PHP and JSON syntax on the changed files; only findings on added or changed lines count |
| test | per changed service: cart (.NET build, analyzers, tests), checkout and product-catalog (Go build, tests, golangci-lint), frontend (TypeScript, ESLint), payment (syntax) |
| build | the image of each changed service, as Deploy builds it, not pushed |
| config | Helm chart rendered with `deploy/` values and validated (kubeconform), feature flags against flagd's schema, dashboards and alert rules (datasources, rule fields, unique uids, PromQL) |
| security | dependency review: new dependencies with known vulnerabilities |

Run a check locally: `deploy/ci.sh lint origin/main`, `deploy/ci.sh test cart origin/main`,
`deploy/ci.sh config`, `deploy/ci.sh observability`.

Workflow **CodeQL** (`.github/workflows/codeql.yml`) scans every language on pushes,
pull requests and weekly; secret scanning with push protection and Dependabot alerts
run on GitHub's side.

## Layout

| Path | What |
|---|---|
| `src/<service>/` | service code (`deploy/services.txt` lists what Deploy can build) |
| `deploy/` | build and deploy scripts, Helm values, pinned images |
| `observability/` | dashboards and alert rules, loaded on every deploy |
| `src/flagd/demo.flagd.json` | feature flags (all faults off) |
