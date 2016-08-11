#!/bin/bash

# Copyright 2016 The Kubernetes Authors All rights reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# This script contains the helper functions that each provider hosting
# Kubernetes must implement to use cluster/kube-*.sh scripts.

set -x

# Must ensure that the following ENV vars are set
function detect-master {
	echo "KUBE_MASTER_IP: $KUBE_MASTER_IP" 1>&2
	echo "KUBE_MASTER: $KUBE_MASTER" 1>&2
}

# Get node names if they are not static.
function detect-node-names {
	echo "NODE_NAMES: [${NODE_NAMES[*]}]" 1>&2
}

# Get node IP addresses and store in KUBE_NODE_IP_ADDRESSES[]
function detect-nodes {
	echo "KUBE_NODE_IP_ADDRESSES: [${KUBE_NODE_IP_ADDRESSES[*]}]" 1>&2
}

# Verify prereqs on host machine
function verify-prereqs {
	echo "Skeleton Provider: verify-prereqs not implemented" 1>&2
}

# Validate a kubernetes cluster
function validate-cluster {
	# by default call the generic validate-cluster.sh script, customizable by
	# any cluster provider if this does not fit.
	"${KUBE_ROOT}/cluster/validate-cluster.sh"
}

# Instantiate a kubernetes cluster
function kube-up {
	echo "Skeleton Provider: kube-up not implemented" 1>&2
}

# Delete a kubernetes cluster
function kube-down {
	echo "Skeleton Provider: kube-down not implemented" 1>&2
}

# Update a kubernetes cluster
function kube-push {
	echo "Skeleton Provider: kube-push not implemented" 1>&2
}

# Prepare update a kubernetes component
function prepare-push {
	echo "Skeleton Provider: prepare-push not implemented" 1>&2
}

# Update a kubernetes master
function push-master {
	echo "Skeleton Provider: push-master not implemented" 1>&2
}

# Update a kubernetes node
function push-node {
	echo "Skeleton Provider: push-node not implemented" 1>&2
}

# Execute prior to running tests to build a release if required for env
function test-build-release {
	echo "Skeleton Provider: test-build-release not implemented" 1>&2
}

# Execute prior to running tests to initialize required structure
function test-setup {
	echo "Skeleton Provider: test-setup not implemented" 1>&2
}

# Execute after running tests to perform any required clean-up
function test-teardown {
	echo "Skeleton Provider: test-teardown not implemented" 1>&2
}

### mods to skeleton

# do nothing
function prepare-e2e {
  :
}

# only needed for gce; do nothing
function detect-project() {
  :
}

# since we're pretending to be aws, cluster/log-dump.sh expects us
# to implement get_ssh_hostname
function get_ssh_hostname() {
  local mynode="$1"

  if [[ "${mynode}" == "${MASTER_NAME}" ]]; then
    echo ${KUBE_MASTER_IP}
  else
    # TODO: how would this work for skeleton... need to pass mapping of
    #       node name to ssh hostname (or ip)

    if [[ "$mynode" =~ "192.168" ]]; then
      # XXX kraken assumptions: in our bare metal setup, node names are routable ip's
      echo $mynode
    else
      # XXX kraken assumptions: in aws, node names are private-ip-addresses, and we can query for their public ip's
      aws ec2 describe-instances \
        --output text \
        --filters Name=private-ip-address,Values=$mynode \
        --query Reservations[].Instances[].NetworkInterfaces[0].Association.PublicIp
    fi
  fi
}

# copy-pasta from aws
function ssh-to-node {
  local node="$1"
  local cmd="$2"

  local ip=$(get_ssh_hostname ${node})

  for try in {1..5}; do
    if ssh -oLogLevel=quiet -oConnectTimeout=30 -oStrictHostKeyChecking=no -i "${AWS_SSH_KEY}" ${SSH_USER}@${ip} "echo test > /dev/null"; then
      break
    fi
    sleep 5
  done
  ssh -oLogLevel=quiet -oConnectTimeout=30 -oStrictHostKeyChecking=no -i "${AWS_SSH_KEY}" ${SSH_USER}@${ip} "${cmd}"
}
