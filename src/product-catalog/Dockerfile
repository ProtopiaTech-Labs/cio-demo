# Copyright The OpenTelemetry Authors
# SPDX-License-Identifier: Apache-2.0


FROM golang:1.24-bookworm AS builder

WORKDIR /usr/src/app/

COPY ./src/product-catalog/go.mod go.mod
COPY ./src/product-catalog/go.sum go.sum

RUN go mod download

COPY ./src/product-catalog/genproto/oteldemo/ genproto/oteldemo/
COPY ./src/product-catalog/products/ products/
COPY ./src/product-catalog/main.go main.go

# CGO_ENABLED=1 required for Pyroscope profiling
RUN CGO_ENABLED=1 GOOS=linux GO111MODULE=on go build -ldflags "-s -w" -o product-catalog main.go

# Use cc image instead of static for CGO binary
FROM gcr.io/distroless/cc-debian12:nonroot

WORKDIR /usr/src/app/

COPY --from=builder /usr/src/app/product-catalog ./product-catalog
COPY --from=builder /usr/src/app/products/ ./products/

EXPOSE ${PRODUCT_CATALOG_PORT}
ENTRYPOINT [ "./product-catalog" ]
