# Copyright The OpenTelemetry Authors
# SPDX-License-Identifier: Apache-2.0


FROM --platform=${BUILDPLATFORM} eclipse-temurin:21-jdk AS builder
ARG _JAVA_OPTIONS
WORKDIR /usr/src/app/

COPY ./src/ad/gradlew* ./src/ad/settings.gradle* ./src/ad/build.gradle ./
COPY ./src/ad/gradle ./gradle

RUN chmod +x ./gradlew
RUN ./gradlew
RUN ./gradlew downloadRepos

COPY ./src/ad/ ./
COPY ./pb/ ./proto
RUN chmod +x ./gradlew
RUN ./gradlew installDist -PprotoSourceDir=./proto

# -----------------------------------------------------------------------------

FROM eclipse-temurin:21-jre

ARG OTEL_JAVA_AGENT_VERSION
ARG _JAVA_OPTIONS

WORKDIR /usr/src/app/

COPY --from=builder /usr/src/app/ ./
ADD --chmod=644 https://github.com/open-telemetry/opentelemetry-java-instrumentation/releases/download/v$OTEL_JAVA_AGENT_VERSION/opentelemetry-javaagent.jar /usr/src/app/opentelemetry-javaagent.jar
ADD --chmod=644 https://github.com/grafana/pyroscope-java/releases/download/v0.14.0/pyroscope.jar /usr/src/app/pyroscope.jar
# Pyroscope OTel extension for span profile linking (adds pyroscope.profile.id to traces).
# The extension starts the Pyroscope agent itself (OTEL_PYROSCOPE_START_PROFILING), so no
# separate -javaagent for pyroscope.jar. 0.10.1.11 (io.pyroscope:otel) threw AssertionError in
# PyroscopeOtelSpanProcessor.onStart with OTel Java agent 2.x and failed most GetAds calls.
ADD --chmod=644 https://github.com/grafana/otel-profiling-java/releases/download/v2.1.4/pyroscope-otel-javaagent-extension.jar /usr/src/app/pyroscope-otel.jar
ENV JAVA_TOOL_OPTIONS="-javaagent:/usr/src/app/opentelemetry-javaagent.jar"
ENV OTEL_JAVAAGENT_EXTENSIONS="/usr/src/app/pyroscope-otel.jar"
ENV PYROSCOPE_APPLICATION_NAME="otel/ad"
ENV PYROSCOPE_FORMAT="jfr"
ENV PYROSCOPE_PROFILER_EVENT="cpu"
ENV OTEL_PYROSCOPE_ADD_PROFILE_URL="true"
ENV OTEL_PYROSCOPE_ADD_PROFILE_BASELINE_URL="true"
ENV OTEL_PYROSCOPE_START_PROFILING="true"

EXPOSE ${AD_PORT}
ENTRYPOINT [ "./build/install/opentelemetry-demo-ad/bin/Ad" ]
