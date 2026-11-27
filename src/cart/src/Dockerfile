# Copyright The OpenTelemetry Authors
# SPDX-License-Identifier: Apache-2.0
# Copyright 2021 Google LLC
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# https://mcr.microsoft.com/v2/dotnet/sdk/tags/list
FROM --platform=$BUILDPLATFORM mcr.microsoft.com/dotnet/sdk:10.0 AS builder
ARG TARGETARCH

WORKDIR /usr/src/app/

COPY ./src/cart/ ./
COPY ./pb/ ./pb/

RUN dotnet restore ./src/cart.csproj -r linux-musl-$TARGETARCH

RUN dotnet publish ./src/cart.csproj -r linux-musl-$TARGETARCH --no-restore -o /cart

# -----------------------------------------------------------------------------

# https://mcr.microsoft.com/v2/dotnet/runtime-deps/tags/list
FROM mcr.microsoft.com/dotnet/runtime-deps:10.0-alpine3.22

WORKDIR /usr/src/app/
COPY --from=builder /cart/ ./

COPY --from=pyroscope/pyroscope-dotnet:0.13.0-musl /Pyroscope.Profiler.Native.so /dotnet/
COPY --from=pyroscope/pyroscope-dotnet:0.13.0-musl /Pyroscope.Linux.ApiWrapper.x64.so /dotnet/
# The profiler loads from CORECLR_PROFILER_PATH (/dotnet), but the managed Pyroscope API
# (PyroscopeSpanProcessor, Profiler.Instance) DllImports "Pyroscope.Profiler.Native" from
# the app directory. A symlink to the same file makes both resolve to one loaded library;
# without it span profiles (traces to profiles) are never recorded.
RUN ln -s /dotnet/Pyroscope.Profiler.Native.so /usr/src/app/Pyroscope.Profiler.Native.so

ENV DOTNET_HOSTBUILDER__RELOADCONFIGONCHANGE=false

EXPOSE ${CART_PORT}
ENTRYPOINT [ "./cart" ]
