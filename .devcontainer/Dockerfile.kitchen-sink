# Start with the standard devcontainers base (Ubuntu-based)
FROM mcr.microsoft.com/devcontainers/base:ubuntu

# Install dependencies (direnv + curl for downloading bazelisk)
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
       direnv curl ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Install Docker CLI
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
       apt-transport-https gnupg lsb-release \
    && install -m 0755 -d /etc/apt/keyrings \
    && curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
       | gpg --dearmor -o /etc/apt/keyrings/docker.gpg \
    && chmod a+r /etc/apt/keyrings/docker.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
       $(lsb_release -cs) stable" > /etc/apt/sources.list.d/docker.list \
    && apt-get update \
    && apt-get install -y --no-install-recommends docker-ce-cli \
    && rm -rf /var/lib/apt/lists/*

# Install kind (Kubernetes in Docker)
RUN curl -Lo /usr/local/bin/kind https://kind.sigs.k8s.io/dl/v0.26.0/kind-linux-amd64 \
    && chmod +x /usr/local/bin/kind

# Install bazelisk (latest release)
RUN curl -Lo /usr/local/bin/bazelisk https://github.com/bazelbuild/bazelisk/releases/latest/download/bazelisk-linux-amd64 \
    && chmod +x /usr/local/bin/bazelisk \
    && ln -s /usr/local/bin/bazelisk /usr/local/bin/bazel

# Hook direnv into bash (default Codespaces shell)
RUN echo 'eval "$(direnv hook bash)"' >> /etc/bash.bashrc
