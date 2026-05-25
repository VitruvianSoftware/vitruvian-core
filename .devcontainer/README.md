# Dev Container Configuration

This directory contains the configuration for the Blueprint development container.

## What's Included

### Base Tools

- **direnv** - Automatic environment management
- **bazelisk** - Bazel version manager (aliased as `bazel`)
- **Docker CLI** - Container management (via host Docker socket)
- **kind** - Kubernetes in Docker for local cluster development

### Additional Tools (via bazel_env)

After running `bazel run //tools:bazel_env`, the following tools are available:

- **kubectl** - Kubernetes CLI
- **skaffold** - Continuous development for Kubernetes
- **gcloud** - Google Cloud CLI
- And many more (see `bazel run //tools:bazel_env` output)

## Docker Setup

The dev container uses **Docker-outside-of-Docker** (DooD), meaning:

- Docker CLI is installed in the container
- Docker daemon runs on the host machine
- The host's Docker socket is mounted at `/var/run/docker.sock`
- Non-root user (vscode) has Docker access via the docker group

This approach:

- ✅ Uses fewer resources (no Docker daemon in container)
- ✅ Shares images with host (no duplication)
- ✅ Works with existing Docker Desktop configurations
- ❌ Requires Docker running on host

## Kubernetes Setup

### kind (Kubernetes in Docker)

**kind** is pre-installed but **no cluster is created by default**. This saves resources when Kubernetes is not needed.

#### Creating a Cluster

```bash
# Create cluster with optimized settings
./tools/kind-cluster.sh create
```

This creates a single-node cluster named `blueprint-dev` with:

- Resource constraints for limited environments
- Port mappings: 8080→80, 8443→443
- Automatic kubectl configuration

#### Cluster Management

```bash
# Check cluster status
./tools/kind-cluster.sh status

# Restart cluster (useful after config changes)
./tools/kind-cluster.sh restart

# Delete cluster (frees ~800MB-1GB)
./tools/kind-cluster.sh delete
```

### Configuration Files

- **`kind-config.yaml`** - kind cluster configuration
  - Defines port mappings
  - Sets resource constraints
  - Single control-plane node for efficiency

- **`Dockerfile`** - Dev container image
  - Base: Microsoft devcontainers Ubuntu image
  - Installs development tools
  - Configures direnv integration

- **`devcontainer.json`** - VS Code dev container settings
  - Mounts Docker socket
  - Configures Docker access for non-root user
  - Runs post-create commands

## Resource Considerations

The dev container is designed for resource-constrained environments:

### Without Kubernetes

- Base container: ~100-200MB
- Bazel cache: Configurable (see `user.bazelrc`)
- Total: ~500MB-1GB

### With Kubernetes (kind cluster)

- Base container: ~100-200MB
- kind cluster: ~800MB-1GB
- Bazel cache: Configurable
- Total: ~1.5-2.5GB

### Tips for Limited Resources

1. **Delete kind cluster when not in use:**

   ```bash
   ./tools/kind-cluster.sh delete
   ```

2. **Configure Bazel cache location:**

   See `/workspaces/blueprint/user.bazelrc` to relocate cache to /tmp

3. **Monitor Docker resources:**

   ```bash
   docker stats
   docker system df
   ```

4. **Clean up unused Docker resources:**

   ```bash
   docker system prune -a
   ```

## Rebuilding the Container

After modifying `Dockerfile` or `devcontainer.json`:

1. **VS Code:** Run command "Dev Containers: Rebuild Container"
2. **CLI:**

   ```bash
   # From outside the container
   docker build -t blueprint-devcontainer .devcontainer/
   ```

## Troubleshooting

### Docker not working

```bash
# Check Docker socket is mounted
ls -l /var/run/docker.sock

# Test Docker access
docker info

# Check user is in docker group
groups | grep docker
```

### kind cluster issues

```bash
# Check Docker is running
docker info

# Delete and recreate cluster
./tools/kind-cluster.sh restart

# View kind logs
kind export logs --name blueprint-dev
```

### kubectl not configured

```bash
# Verify cluster exists
kind get clusters

# Set context manually
kubectl cluster-info --context kind-blueprint-dev

# Or recreate cluster
./tools/kind-cluster.sh restart
```

### Out of disk space

See the [Troubleshooting Guide](../docs/user/troubleshooting.md) for disk space management, including:

- Relocating Bazel cache
- Cleaning Docker resources
- Monitoring disk usage

## Customization

### Adding Tools to Dockerfile

To add system packages:

```dockerfile
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
       your-package-here \
    && rm -rf /var/lib/apt/lists/*
```

### Adding Tools via bazel_env

To add cross-platform CLI tools, see [Development Guide](../docs/contributor/development.md#add-new-tool).

### Modifying kind Configuration

Edit `.devcontainer/kind-config.yaml` to:

- Change port mappings
- Add worker nodes (increases resource usage)
- Adjust resource limits
- Enable feature gates

After changes, restart the cluster:

```bash
./tools/kind-cluster.sh restart
```

## References

- [Dev Containers Documentation](https://containers.dev/)
- [kind Documentation](https://kind.sigs.k8s.io/)
- [Docker Documentation](https://docs.docker.com/)
- [Blueprint Development Guide](../docs/contributor/development.md)
