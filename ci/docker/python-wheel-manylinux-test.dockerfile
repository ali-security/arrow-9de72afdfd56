# Licensed to the Apache Software Foundation (ASF) under one
# or more contributor license agreements.  See the NOTICE file
# distributed with this work for additional information
# regarding copyright ownership.  The ASF licenses this file
# to you under the Apache License, Version 2.0 (the
# "License"); you may not use this file except in compliance
# with the License.  You may obtain a copy of the License at
#
#   http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing,
# software distributed under the License is distributed on an
# "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
# KIND, either express or implied.  See the License for the
# specific language governing permissions and limitations
# under the License.

ARG arch
ARG python

# minio server and client for the S3 tests. The dl.min.io archive URLs
# install_minio.sh fetches answer 410 Gone, so take the server from the
# conda-forge build of the last release before 14.0.2, and build the
# 2022-05-09 mc client install_minio.sh pins (newer mc releases dropped the
# "admin policy add/set" commands the limited-user S3 tests run).
FROM ${arch}/golang:1.24-bookworm AS minio
RUN apt-get update -y -q && \
    apt-get install -y -q --no-install-recommends unzip zstd && \
    rm -rf /var/lib/apt/lists/*
RUN CGO_ENABLED=0 GOBIN=/minio/bin go install \
      -ldflags "-X github.com/minio/mc/cmd.ReleaseTag=RELEASE.2022-05-09T04-08-26Z -X github.com/minio/mc/cmd.Version=2022-05-09T04:08:26Z" \
      github.com/minio/mc@RELEASE.2022-05-09T04-08-26Z && \
    /minio/bin/mc --version
RUN case "$(uname -m)" in \
      x86_64) subdir=linux-64; build=hbcca054_0 ;; \
      aarch64) subdir=linux-aarch64; build=hcefe29a_0 ;; \
    esac && \
    cd /tmp && \
    curl -fsSL --retry 5 -o minio.conda https://conda.anaconda.org/conda-forge/${subdir}/minio-server-2023.11.20.22.40.07-${build}.conda && \
    unzip -q minio.conda 'pkg-*.tar.zst' && \
    tar --zstd -xf pkg-*.tar.zst -C /minio bin/minio && \
    /minio/bin/minio --version

# bookworm: the base the floating tag pointed at when 14.0.2 was released
# (newer bases ship no time zone database, which the ORC reader aborts on)
FROM ${arch}/python:${python}-bookworm

# RUN pip install --upgrade pip

# pandas doesn't provide wheel for aarch64 yet, so cache the compiled
# test dependencies in a docker image
ARG pip_index_url=https://pypi.org/simple
COPY python/requirements-wheel-test.txt /arrow/python/
RUN PIP_INDEX_URL=${pip_index_url} pip install -r /arrow/python/requirements-wheel-test.txt

COPY ci/scripts/install_gcs_testbench.sh /arrow/ci/scripts/
RUN PYTHON=python /arrow/ci/scripts/install_gcs_testbench.sh default

# test_gdb needs gdb
RUN apt-get update -y -q && \
    apt-get install -y -q --no-install-recommends gdb && \
    rm -rf /var/lib/apt/lists/*
COPY --from=minio /minio/bin/ /usr/local/bin/
