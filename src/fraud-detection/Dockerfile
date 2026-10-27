# Copyright The OpenTelemetry Authors
# SPDX-License-Identifier: Apache-2.0


FROM --platform=${BUILDPLATFORM} gradle:8-jdk17 AS builder

WORKDIR /usr/src/app/

COPY ./src/fraud-detection/ ./
COPY ./pb/ ./src/main/proto/

RUN gradle shadowJar

# -----------------------------------------------------------------------------

FROM gcr.io/distroless/java17-debian12:nonroot

ARG OTEL_JAVA_AGENT_VERSION
WORKDIR /usr/src/app/

ADD --chmod=644 https://github.com/open-telemetry/opentelemetry-java-instrumentation/releases/download/v$OTEL_JAVA_AGENT_VERSION/opentelemetry-javaagent.jar /usr/src/app/opentelemetry-javaagent.jar
ADD --chmod=644 https://github.com/grafana/pyroscope-java/releases/download/v0.14.0/pyroscope.jar /usr/src/app/pyroscope.jar
# Pyroscope OTel extension for span profile linking (adds pyroscope.profile.id to traces)
ADD --chmod=644 https://repo1.maven.org/maven2/io/pyroscope/otel/0.10.1.11/otel-0.10.1.11.jar /usr/src/app/pyroscope-otel.jar
ENV JAVA_TOOL_OPTIONS="-javaagent:/usr/src/app/opentelemetry-javaagent.jar"
ENV OTEL_JAVAAGENT_EXTENSIONS="/usr/src/app/pyroscope-otel.jar"
ENV PYROSCOPE_APPLICATION_NAME="otel/fraud-detection"
ENV PYROSCOPE_FORMAT="jfr"
ENV PYROSCOPE_PROFILER_EVENT="cpu"
ENV OTEL_PYROSCOPE_ADD_PROFILE_URL="true"
ENV OTEL_PYROSCOPE_ADD_PROFILE_BASELINE_URL="true"
ENV OTEL_PYROSCOPE_START_PROFILING="true"

COPY --from=builder /usr/src/app/build/libs/fraud-detection-1.0-all.jar fraud-detection-1.0-all.jar

ENTRYPOINT [ "java", "-jar", "fraud-detection-1.0-all.jar" ]
