#!/bin/bash -
#title           :utils.sh
#description     :utils
#author          :Samsung SDSRA
#==============================================================================

set -x

my_dir=$(dirname "${BASH_SOURCE}")

# set KRAKEN_ROOT to absolute path for use in other scripts
readonly KRAKEN_ROOT=$(cd "${my_dir}/.."; pwd)
KRAKEN_VERBOSE=${KRAKEN_VERBOSE:-false}

function warn {
  echo -e "\033[1;33mWARNING: $1\033[0m"
}

function error {
  echo -e "\033[0;31mERROR: $1\033[0m"
}

function inf {
  echo -e "\033[0;32m$1\033[0m"
}

function follow {
  inf "Following docker logs now. Ctrl-C to cancel."
  docker logs --follow $1
}

function run_command {
  inf "Running:\n $1"
  if ${KRAKEN_VERBOSE}; then
    eval $1
  else
    eval $1 &> /dev/null
  fi
}

function setup_dockermachine {
  local dm_command="docker-machine create ${KRAKEN_DOCKER_MACHINE_OPTIONS} ${KRAKEN_DOCKER_MACHINE_NAME}"
  inf "Starting docker-machine with:\n  '${dm_command}'"

  eval ${dm_command}
}

while [[ $# > 0 ]]
do
  key="$1"
  shift

  if [ -z ${1+x} ]; then 
    value=""
  else 
    # don't shift yet, don't know if we'll use value until key is matched
    value="$1"
  fi

  case $key in
    --clustertype)
    KRAKEN_CLUSTER_TYPE=$value
    shift
    ;;
    --clustername)
    KRAKEN_CLUSTER_NAME=$value
    shift
    ;;
    --dmopts)
    KRAKEN_DOCKER_MACHINE_OPTIONS=$value
    shift
    ;;
    --dmname)
    KRAKEN_DOCKER_MACHINE_NAME=$value
    shift
    ;;
    --dmshell)
    KRAKEN_DOCKER_MACHINE_SHELL=$value
    shift
    ;;
    --terraform-retries)
    TERRAFORM_RETRIES=$value
    shift
    ;;
    --aws-credential-directory)
    AWS_CREDENTIAL_DIRECTORY=$value
    shift
    ;;
    --verbose)
    KRAKEN_VERBOSE=true
    ;;
    *)
      # unknown option
      inf "Ignoring garbage argument: $key"
    ;;
  esac

done

KRAKEN_NATIVE_DOCKER=false
if docker ps &> /dev/null; then
  if [ -z ${KRAKEN_DOCKER_MACHINE_NAME+x} ]; then
    inf "Using docker natively"
    KRAKEN_NATIVE_DOCKER=true
    KRAKEN_DOCKER_MACHINE_NAME="localhost"
  fi
fi

if [ -z ${KRAKEN_DOCKER_MACHINE_NAME+x} ]; then
  error "--dmname not specified. Docker Machine name is required."
  exit 1
fi

if [ -z ${KRAKEN_CLUSTER_TYPE+x} ]; then
  error "--clustertype not specified. Cluster type is required."
  exit 1
fi

if [ -z ${KRAKEN_CLUSTER_NAME+x} ]; then
  error "--clustername not specified. Cluster name is required."
  exit 1
fi

if [ ${KRAKEN_CLUSTER_TYPE} == "local" ]; then
  error "local --clustertype is not supported"
  exit 1
fi

if [ ! -f "${KRAKEN_ROOT}/terraform/${KRAKEN_CLUSTER_TYPE}/${KRAKEN_CLUSTER_NAME}/terraform.tfvars" ]; then
  warn "${KRAKEN_ROOT}/terraform/${KRAKEN_CLUSTER_TYPE}/${KRAKEN_CLUSTER_NAME}/terraform.tfvars is not present."
fi

if [ "${KRAKEN_NATIVE_DOCKER}" = false ]; then
  if docker-machine ls -q | grep --silent "${KRAKEN_DOCKER_MACHINE_NAME}"; then
    inf "Machine ${KRAKEN_DOCKER_MACHINE_NAME} already exists."
  else
    if [ -z ${KRAKEN_DOCKER_MACHINE_OPTIONS+x} ]; then
      error "--dmopts not specified. Docker Machine option string is required unless machine ${KRAKEN_DOCKER_MACHINE_NAME} already exists."
      exit 1
    fi
    setup_dockermachine
  fi

  if [ -z ${KRAKEN_DOCKER_MACHINE_SHELL+x} ]; then
    eval "$(docker-machine env ${KRAKEN_DOCKER_MACHINE_NAME})"
  else
    eval "$(docker-machine env ${KRAKEN_DOCKER_MACHINE_NAME} --shell ${KRAKEN_DOCKER_MACHINE_SHELL})"
  fi
fi

AWS_CREDENTIAL_DIRECTORY="${AWS_CREDENTIAL_DIRECTORY:-"${HOME}/.aws"}"
if [ "${KRAKEN_NATIVE_DOCKER}" = false ] ; then
  KRAKEN_AWS_CREDENTIAL_DIRECTORY="$(docker-machine ssh ${KRAKEN_DOCKER_MACHINE_NAME} "cd && pwd")/.aws"
else
  KRAKEN_AWS_CREDENTIAL_DIRECTORY="${AWS_CREDENTIAL_DIRECTORY}"
fi

# common / global variables for use in scripts
readonly KRAKEN_CONTAINER_IMAGE_NAME="samsung_cnct/kraken:${KRAKEN_CLUSTER_NAME}"
readonly KRAKEN_CONTAINER_NAME="kraken_cluster_${KRAKEN_CLUSTER_NAME}"

exit

# create the data volume container for state
if docker inspect kraken_data &> /dev/null; then
  inf "Data volume container kraken_data already exists."
else
  run_command "docker create -v /kraken_data --name kraken_data busybox /bin/sh"
fi
