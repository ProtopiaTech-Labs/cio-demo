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

Changes reach `main` through pull requests.

## Layout

| Path | What |
|---|---|
| `src/<service>/` | service code (`deploy/services.txt` lists what Deploy can build) |
| `deploy/` | build and deploy scripts, Helm values, pinned images |
| `observability/` | dashboards and alert rules, loaded on every deploy |
| `src/flagd/demo.flagd.json` | feature flags (all faults off) |
