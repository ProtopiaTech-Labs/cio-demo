# Astronomy Shop: instructions for Copilot

The OpenTelemetry Demo shop on Kubernetes, observed with the Grafana stack (Prometheus,
Loki, Tempo, Pyroscope). Branch `main` deploys to production (namespace `cio-demo`) on
every push, so every pull request to `main` is a production change.

## Repository

- `src/<service>/`: one directory per microservice, each in its own language: cart (C#),
  checkout and product-catalog (Go), frontend (TypeScript, Next.js), payment (Node.js),
  ad and fraud-detection (Java/Kotlin), currency (C++), shipping (Rust), quote (PHP),
  email (Ruby), recommendation, product-reviews, llm, load-generator (Python).
  Services talk over gRPC (`pb/demo.proto`) and Kafka (orders).
- `deploy/`: build and deploy scripts, Helm values (`values.yaml`, `values.cio-demo.yaml`),
  pinned images. `deploy/ci.sh` holds the checks of workflow CI.
- `observability/`: Grafana dashboards (JSON) and alert rules (Grafana file-provisioning
  YAML), loaded into Grafana on every deploy.
- `src/flagd/demo.flagd.json`: feature flags; every fault flag stays `off`.

## Reviewing a pull request

Focus on what breaks production, not on style (linters check style on changed lines):

- Behaviour changes hidden in refactors: a "simplification" must keep the semantics
  of the code it replaces, including empty, missing and duplicate inputs and the
  exceptions a call can throw.
- Error handling on request paths: an exception that escapes a gRPC or HTTP handler
  becomes a 500 for the user. Errors carry enough context to diagnose them.
- Telemetry: new code paths keep spans, span attributes and logs consistent with the
  surrounding code (OpenTelemetry semantic conventions); no personal data (card numbers,
  emails, addresses) in attributes or logs.
- Resources in Helm values: limits that are too low cause OOM kills and restarts of
  stateful services (valkey-cart keeps carts in memory only).
- Alert rules: a rule has a `uid`, `title`, `condition` that names one of its `data`
  refIds, and queries the datasources `prometheus`, `loki` or `tempo`; labels
  `sre_agent` and `holmes` start the SRE agent and are not for new rules.

## Conventions

- Commit messages: Conventional Commits (`fix(cart): ...`, `feat(checkout): ...`).
- Pull requests that work on an incident issue say `Refs #<issue>`, never `Fixes`: the
  issue closes after the fix is verified in production.
- Keep fixes minimal and in the style of the surrounding code; one concern per pull request.
