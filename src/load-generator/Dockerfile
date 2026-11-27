# Copyright The OpenTelemetry Authors
# SPDX-License-Identifier: Apache-2.0


FROM python:3.12-slim-bookworm AS base

FROM base AS builder
RUN apt-get -qq update \
    && apt-get install -y --no-install-recommends g++ \
    && rm -rf /var/lib/apt/lists/*

COPY ./src/load-generator/requirements.txt .
RUN pip install --prefix="/reqs" -r requirements.txt

FROM base
WORKDIR /usr/src/app/
COPY --from=builder /reqs /usr/local
ENV PLAYWRIGHT_BROWSERS_PATH=/opt/pw-browsers
# Playwright's bundled Node needs libatomic1 to run "playwright install" at all
# (missing from python:3.12-slim-bookworm; --with-deps installs Chromium's libs only).
RUN apt-get -qq update     && apt-get install -y --no-install-recommends libatomic1     && rm -rf /var/lib/apt/lists/*     && playwright install --with-deps chromium
COPY ./src/load-generator/locustfile.py .
COPY ./src/load-generator/people.json .
ENTRYPOINT ["locust", "--skip-log-setup"]
