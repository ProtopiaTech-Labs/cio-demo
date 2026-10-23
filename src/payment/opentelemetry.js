// Copyright The OpenTelemetry Authors
// SPDX-License-Identifier: Apache-2.0

// pino's OTLP log transport (logger.js) runs in a worker thread, and worker threads
// inherit --require=./opentelemetry.js. Without this guard the worker starts a second
// OTel SDK and a second Pyroscope profiler: duplicate profiles, and the same metric
// series exported twice, whose interleaved samples Prometheus rejects as out of order.
const { isMainThread } = require('worker_threads');

if (isMainThread) {
  // Initialize Pyroscope profiler
  const Pyroscope = require('@pyroscope/nodejs');
  if (process.env.PYROSCOPE_SERVER_ADDRESS) {
    Pyroscope.init({
      serverAddress: process.env.PYROSCOPE_SERVER_ADDRESS,
      appName: process.env.PYROSCOPE_APPLICATION_NAME || 'payment',
    });
    Pyroscope.start();
  }

  const opentelemetry = require("@opentelemetry/sdk-node")
  const {getNodeAutoInstrumentations} = require("@opentelemetry/auto-instrumentations-node")
  const {OTLPTraceExporter} = require('@opentelemetry/exporter-trace-otlp-grpc')
  const {OTLPMetricExporter} = require('@opentelemetry/exporter-metrics-otlp-grpc')
  const {PeriodicExportingMetricReader} = require('@opentelemetry/sdk-metrics')
  const {alibabaCloudEcsDetector} = require('@opentelemetry/resource-detector-alibaba-cloud')
  const {awsEc2Detector, awsEksDetector} = require('@opentelemetry/resource-detector-aws')
  const {containerDetector} = require('@opentelemetry/resource-detector-container')
  const {gcpDetector} = require('@opentelemetry/resource-detector-gcp')
  const {envDetector, hostDetector, osDetector, processDetector} = require('@opentelemetry/resources')
  const {RuntimeNodeInstrumentation} = require('@opentelemetry/instrumentation-runtime-node')

  const sdk = new opentelemetry.NodeSDK({
    traceExporter: new OTLPTraceExporter(),
    instrumentations: [
      getNodeAutoInstrumentations({
        // only instrument fs if it is part of another trace
        '@opentelemetry/instrumentation-fs': {
          requireParentSpan: true,
        },
      }),
      new RuntimeNodeInstrumentation({
        monitoringPrecision: 5000,
      })
    ],
    metricReader: new PeriodicExportingMetricReader({
      exporter: new OTLPMetricExporter()
    }),
    resourceDetectors: [
      containerDetector,
      envDetector,
      hostDetector,
      osDetector,
      processDetector,
      alibabaCloudEcsDetector,
      awsEksDetector,
      awsEc2Detector,
      gcpDetector
    ],
  })

  sdk.start();
}
