# Copyright (c) 2026 VitruvianSoftware
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.

# vitruvian-ci-runner: the image the homelab merge-queue runners run
# (gitops/argocd/platform/actions-runners, runner scale set "vitruvian-queue").
# Spec: docs/superpowers/specs/2026-10-19-queue-runners-on-homelab-design.md §3
#
# Ubuntu 26.04, like GitHub's hosted ubuntu-26.04 image the queue jobs were
# written for: .github/actions/setup-bazel runs `sudo dpkg -i` on 26.04
# packages, which the stock actions-runner image (an older Ubuntu) cannot.
# Plus the GitHub Actions runner, passwordless sudo for its user, and the tools
# the queue jobs take from the hosted image. Every input is pinned: the base
# by digest, the runner by version and SHA-256.
FROM ubuntu:26.04@sha256:c098726dd9b9733f3e885f8de0ef375206a311b0a317eadc40d347b1115fb944

ARG RUNNER_VERSION=2.338.0
ARG RUNNER_SHA256=af4b794c1bc41d73d40535e3fe092a39f9679cd8d965954c2aca25a05ca41d32

ENV DEBIAN_FRONTEND=noninteractive \
    RUNNER_MANUALLY_TRAP_SIG=1 \
    ACTIONS_RUNNER_PRINT_LOG_TO_STDOUT=1

# What the queue jobs use from the hosted image. build-essential and python3
# for Bazel's toolchains and the repo's scripts; shellcheck (actionlint.yaml
# relies on it being preinstalled), node and npm (migration-safety runs npx)
# and gh; the rest for checkout, setup-* actions and the archives they unpack.
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      build-essential ca-certificates curl gh git git-lfs gnupg jq lsb-release \
      nodejs npm python3 python3-pip python3-venv shellcheck sudo tzdata \
      unzip xz-utils zip zstd \
 && rm -rf /var/lib/apt/lists/*

# bazel: GitHub's hosted image ships bazelisk as `bazel`; setup-bazel only
# caches it. The queue jobs run `bazel` directly, so it must be on the PATH
# (bazelisk picks the version from .bazelversion). Pinned by SHA-256.
ARG BAZELISK_VERSION=1.27.0
ARG BAZELISK_SHA256=e1508323f347ad1465a887bc5d2bfb91cffc232d11e8e997b623227c6b32fb76
RUN curl -fsSL -o /usr/local/bin/bazelisk \
      "https://github.com/bazelbuild/bazelisk/releases/download/v${BAZELISK_VERSION}/bazelisk-linux-amd64" \
 && echo "${BAZELISK_SHA256}  /usr/local/bin/bazelisk" | sha256sum -c - \
 && chmod 0755 /usr/local/bin/bazelisk \
 && ln -s bazelisk /usr/local/bin/bazel

# rustc: .github/actions/build-ci-tool compiles tools/ci with the runner's
# rustc. Without one it falls back to an unpinned `apt-get install rustc`
# (#4183), so install it here, pinned by SHA-256 like everything above. The
# version is the Bazel Rust toolchain's (rust.toolchain in MODULE.bazel), the
# one //tools/ci:build_ci_tool_test proves every tool builds with. Only the
# compiler and its x86_64 std, from the official standalone installer.
ARG RUST_VERSION=1.75.0
ARG RUST_SHA256=6bf166ddcad545aa26aa2d12a186454d7697133b52b7fbbd271ce3ee1ecfedc6
RUN curl -fsSL -o /tmp/rust.tar.xz \
      "https://static.rust-lang.org/dist/rust-${RUST_VERSION}-x86_64-unknown-linux-gnu.tar.xz" \
 && echo "${RUST_SHA256}  /tmp/rust.tar.xz" | sha256sum -c - \
 && mkdir /tmp/rust \
 && tar -xJf /tmp/rust.tar.xz -C /tmp/rust --strip-components=1 \
 && /tmp/rust/install.sh --prefix=/usr/local --disable-ldconfig \
      --components=rustc,rust-std-x86_64-unknown-linux-gnu \
 && rm -rf /tmp/rust /tmp/rust.tar.xz \
 && rustc --version

# The runner user, uid 1001 as ARC's pods run it, with passwordless sudo.
RUN useradd --create-home --uid 1001 --shell /bin/bash runner \
 && echo 'runner ALL=(ALL) NOPASSWD:ALL' >/etc/sudoers.d/runner \
 && chmod 0440 /etc/sudoers.d/runner

WORKDIR /home/runner
RUN curl -fsSL -o runner.tar.gz \
      "https://github.com/actions/runner/releases/download/v${RUNNER_VERSION}/actions-runner-linux-x64-${RUNNER_VERSION}.tar.gz" \
 && echo "${RUNNER_SHA256}  runner.tar.gz" | sha256sum -c - \
 && tar -xzf runner.tar.gz \
 && rm runner.tar.gz \
 && ./bin/installdependencies.sh \
 && rm -rf /var/lib/apt/lists/* \
 && chown -R runner:runner /home/runner

USER runner
# ARC starts /home/runner/run.sh itself (the scale set's container command).
