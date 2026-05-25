#!/usr/bin/env bash

set -e

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

CLUSTER_NAME="local-dev-cluster"
CONFIG_FILE=".devcontainer/kind-config.yaml"

function print_success() {
	echo -e "${GREEN}✓${NC} $1"
}

function print_warning() {
	echo -e "${YELLOW}⚠${NC} $1"
}

function print_error() {
	echo -e "${RED}✗${NC} $1"
}

function check_docker() {
	if ! docker info >/dev/null 2>&1; then
		print_error "Docker is not running. Please ensure Docker is started."
		exit 1
	fi
	print_success "Docker is running"
}

function cluster_exists() {
	kind get clusters 2>/dev/null | grep -q "^${CLUSTER_NAME}$"
}

function create_cluster() {
	echo "Creating kind cluster '${CLUSTER_NAME}'..."

	if cluster_exists; then
		print_warning "Cluster '${CLUSTER_NAME}' already exists"
		return 0
	fi

	kind create cluster --config="${CONFIG_FILE}" --wait=5m
	print_success "Cluster created successfully"

	# Set kubectl context
	kubectl cluster-info --context "kind-${CLUSTER_NAME}"
	print_success "kubectl configured to use kind-${CLUSTER_NAME}"
}

function delete_cluster() {
	echo "Deleting kind cluster '${CLUSTER_NAME}'..."

	if ! cluster_exists; then
		print_warning "Cluster '${CLUSTER_NAME}' does not exist"
		return 0
	fi

	kind delete cluster --name="${CLUSTER_NAME}"
	print_success "Cluster deleted successfully"
}

function status_cluster() {
	if cluster_exists; then
		print_success "Cluster '${CLUSTER_NAME}' is running"
		print_success "Context '$(kubectl config current-context 2>/dev/null)' is active"
		echo ""
		echo "Cluster info:"
		# kubectl cluster-info --context "kind-${CLUSTER_NAME}" 2>/dev/null || true
		kubectl cluster-info 2>/dev/null || true
		echo ""
		echo "Nodes:"
		# kubectl get nodes --context "kind-${CLUSTER_NAME}" 2>/dev/null || true
		kubectl get nodes 2>/dev/null || true
	else
		print_warning "Cluster '${CLUSTER_NAME}' does not exist"
		echo ""
		echo "Run './tools/kind-cluster.sh create' to create a cluster"
	fi
}

function restart_cluster() {
	echo "Restarting kind cluster '${CLUSTER_NAME}'..."
	delete_cluster
	create_cluster
}

function rename_context() {
	local current_context
	current_context=$(kubectl config current-context 2>/dev/null)

	if [ -z "$current_context" ]; then
		print_error "No current context found"
		exit 1
	fi

	echo "Current context: ${current_context}"
	echo -n "Rename context to 'dev-local'? (yes/no): "
	read -r response

	if [ "$response" = "yes" ]; then
		kubectl config rename-context "$current_context" "dev-local"
		print_success "Context renamed from '${current_context}' to 'dev-local'"
		kubectl config use-context "dev-local"
		print_success "Switched to context 'dev-local'"
	else
		print_warning "Context rename cancelled"
	fi
}

function show_help() {
	cat <<EOF
Usage: $0 <command>

Commands:
    create          Create a new kind cluster
    delete          Delete the kind cluster
    restart         Restart the kind cluster (delete + create)
    status          Show cluster status
    rename-context  Rename the current kubectl context to 'dev-local'
    help            Show this help message

Examples:
    $0 create       # Create the cluster
    $0 status       # Check if cluster is running
    $0 delete       # Remove the cluster

The cluster is configured with:
  - Single control-plane node (resource-efficient)
  - Port mappings: 8080->80, 8443->443
  - Resource constraints for limited environments

After creating the cluster:
  - kubectl is automatically configured
  - Context: kind-${CLUSTER_NAME}
  - Access services at localhost:8080 (HTTP) or localhost:8443 (HTTPS)

EOF
}

# Main script
case "${1:-help}" in
create)
	check_docker
	create_cluster
	;;
delete)
	check_docker
	delete_cluster
	;;
restart)
	check_docker
	restart_cluster
	;;
status)
	check_docker
	status_cluster
	;;
rename-context)
	rename_context
	;;
help | --help | -h)
	show_help
	;;
*)
	print_error "Unknown command: $1"
	echo ""
	show_help
	exit 1
	;;
esac
