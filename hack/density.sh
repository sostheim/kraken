#!/bin/bash
set -x

KUBE_DENSITY_KUBECONFIG=${KUBE_DENSITY_KUBECONFIG:-"$HOME/.kube/config"}
KUBE_DENSITY_OUTPUT_DIR=${KUBE_DENSITY_OUTPUT_DIR:-"$(pwd)/output/density"}
KUBE_DENSITY_SSH_USER=${KUBE_DENSITY_SSH_USER:-"core"}
KUBE_DENSITY_SSH_KEY=${KUBE_DENSITY_SSH_KEY:-"${HOME}/.ssh/id_rsa"}

if [[ $# < 2 ]]; then
  echo "Usage: $0 kubernetes_install_dir pods_per_node"
  echo "Switches to given directory assumed to contain kubernetes binaries and runs a single density test"
  echo "  eg: $0 ~/sandbox/kubernetes-1.3.3 10"
  exit 1
fi

KUBE_ROOT=$1
KUBE_DENSITY_PODS_PER_NODE=$2

pushd "${KUBE_ROOT}"

echo "Density test run start date: $(date -u)"
echo "Density test dir: ${KUBE_ROOT}"
echo "Density test kubeconfig: ${KUBE_DENSITY_KUBECONFIG}"

function run_hack_e2e_go() {
  # XXX: e2e-internal scripts assume KUBERNETES_PROVIDER=gce,
  #      which assumes gcloud is present and configured; instead
  #      set a provider that has fewer dependencies
  export KUBERNETES_PROVIDER=aws

  # XXX: e2e-internal scripts require USER to be set
  export USER=${USER:-$(whoami)}

  # avoid provider-specific e2e setup
  export KUBERNETES_CONFORMANCE_TEST="y"

  # specify which cluster to talk to, and what credentials to use
  export KUBECONFIG=${KUBE_DENSITY_KUBECONFIG}

  common_test_args=()
  common_test_args+=("--ginkgo.v=true")
  common_test_args+=("--ginkgo.noColor=true")

  test_args=()
  test_args+=("--ginkgo.focus=should\sallow\sstarting\s${KUBE_DENSITY_PODS_PER_NODE}\spods\sper\snode")
  test_args+=("--e2e-output-dir=${KUBE_DENSITY_OUTPUT_DIR}")
  test_args+=("--report-dir=${KUBE_DENSITY_OUTPUT_DIR}")

  export KUBE_SSH_USER=${KUBE_SSH_USER:-"${KUBE_DENSITY_SSH_USER}"}
  # Provider specific args are currently required for SSH access. Note that
  # https://github.com/kubernetes/kubernetes/issues/20919 suggests that we
  # would like to fix kubernetes so that --provider is no longer necessary.
  export AWS_SSH_KEY=${AWS_SSH_KEY:-"${KUBE_DENSITY_SSH_KEY}"}
  test_args+=("--provider=aws")
  test_args+=("--gce-zone=us-west-2")

  # finish up with remaining cases in serial
  go run hack/e2e.go --v --test --test_args="${common_test_args[*]} ${test_args[*]}" --check_version_skew=false
}

echo
echo "Running density test..."
run_hack_e2e_go
density_result=$?

popd

echo
echo "Density test run stop date: $(date -u)"
exit $density_result
