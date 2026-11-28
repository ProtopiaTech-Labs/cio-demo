# Copyright The OpenTelemetry Authors
# SPDX-License-Identifier: Apache-2.0


FROM apache/kafka:3.9.1

USER root
ARG OTEL_JAVA_AGENT_VERSION

USER appuser

ADD --chown=appuser:appuser https://github.com/open-telemetry/opentelemetry-java-instrumentation/releases/download/v$OTEL_JAVA_AGENT_VERSION/opentelemetry-javaagent.jar /tmp/opentelemetry-javaagent.jar
ADD --chown=appuser:appuser https://github.com/grafana/pyroscope-java/releases/download/v0.14.0/pyroscope.jar /tmp/pyroscope.jar
# Pyroscope OTel extension for span profile linking (adds pyroscope.profile.id to traces)
ADD --chown=appuser:appuser https://repo1.maven.org/maven2/io/pyroscope/otel/0.10.1.11/otel-0.10.1.11.jar /tmp/pyroscope-otel.jar

ENV KAFKA_CONTROLLER_LISTENER_NAMES=CONTROLLER
ENV KAFKA_LISTENER_SECURITY_PROTOCOL_MAP=CONTROLLER:PLAINTEXT,PLAINTEXT:PLAINTEXT
ENV KAFKA_GROUP_INITIAL_REBALANCE_DELAY_MS=0
ENV KAFKA_PROCESS_ROLES=controller,broker
ENV KAFKA_NODE_ID=1
ENV KAFKA_METADATA_LOG_SEGMENT_MS=15000
ENV KAFKA_METADATA_MAX_RETENTION_MS=60000
ENV KAFKA_METADATA_LOG_MAX_RECORD_BYTES_BETWEEN_SNAPSHOTS=2800
ENV KAFKA_AUTO_CREATE_TOPICS_ENABLE=true
ENV KAFKA_OFFSETS_TOPIC_REPLICATION_FACTOR=1
ENV KAFKA_TRANSACTION_STATE_LOG_REPLICATION_FACTOR=1
ENV KAFKA_OPTS="-javaagent:/tmp/opentelemetry-javaagent.jar -Dotel.jmx.target.system=kafka-broker -Dotel.javaagent.extensions=/tmp/pyroscope-otel.jar"
ENV PYROSCOPE_APPLICATION_NAME="otel/kafka"
ENV PYROSCOPE_FORMAT="jfr"
ENV PYROSCOPE_PROFILER_EVENT="cpu"
ENV OTEL_PYROSCOPE_ADD_PROFILE_URL="true"
ENV OTEL_PYROSCOPE_ADD_PROFILE_BASELINE_URL="true"
ENV OTEL_PYROSCOPE_START_PROFILING="true"
ENV CLUSTER_ID=ckjPoprWQzOf0-FuNkGfFQ
