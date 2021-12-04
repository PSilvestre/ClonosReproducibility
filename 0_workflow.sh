#!/bin/bash

PRE_FLIGHT=0

REMOTE=0
REMOTE_ADDR=""

DATA_GENERATOR_IPS=""

BUILD_DOCKER_IMAGES_FROM_SRC=1

CLONOS_IMG="psylvan/clonos_test" #TODO rebuild and reupload images. Change this.
FLINK_IMG="psylvan/flink"

function usage() {
  echo "Clonos Reproducibility:"
  echo -e "\t -p \t\t\t - Uses [p]re-built images of Flink and Clonos. Skips building docker images from artifact source (They should be identical)."
  echo -e "\t -r [user@ip] \t\t - Run experiments [r]emotely on Kubernetes cluster whose master node is provided. Need passwordless ssh into the machine."
  echo -e "\t -g [semi-colon separated list of user@IP which can be ssh'ed into] \t\t - Uses the provided hosts as data-[g]enerators for synthetic tests."
  echo -e "\t\t\t\t\t\t Requires password-less SSH. Each host must have the kafka directory in their home. Most likely not needed."
  echo -e "\t -c \t\t\t - Confirms you have completed the pre-flight [c]hecks."
  echo -e "\t -h \t\t\t - shows [h]elp."
}

function pre_flight_check() {
  echo -e "Pre-flight check flag (-c) was not passed, please read the following:"
  echo -e "Dependencies:"
  echo -e "\t\t\t General: java8, python3.8, gradle 7"
  echo -e "\t\t\t If building containers from source (DEFAULT): git, maven 3.2.5"
  echo -e "\t\t\t If local experiments (DEFAULT): docker, docker-compose"
  echo -e "\t\t\t If remote experiments (-r): kubectl, helm"
  echo -e ""
  echo -e "Testing distributed data-intensive systems at scale is complicated. We have tried to automate it as much as possible, but some work is still required if using Kubernetes (-r option):"
  echo -e "\t\t\t Ensure you have a deployed cluster with enough capacity and copied the kube config to your local machine (~/.kube/config)."
  echo -e "\t\t\t Docker now unfortunately limits image downloads. To ensure no problems, a Docker account with sufficient daily image pulls (https://www.docker.com/pricing) can be created as the free plan may hit its limits."
  echo -e "\t\t\t Once an account (free or not) is created, create a Kubernetes service account so the cluster uses this identity to pull images:"
  echo -e "\t\t\t\t\t\t 1. docker login"
  echo -e "\t\t\t\t\t\t 2. kubectl create secret generic pubregcred --from-file=.dockerconfigjson=<path/to/.docker/config.json> --type=kubernetes.io/dockerconfigjson"
  echo -e "\t\t\t\t\t\t 3. Place the resulting file in the 'kubernetes' directory of this project"
  echo -e ""
  echo -e "Call this script again using the -c flag to certify you have completed the pre-flight check."
}

echoerr() {
  echo "ERROR: $@" 1>&2
  usage
}

echoinfo() { echo "INFO: $@"; }

function parse_inputs() {
  optstring=":hpr:g:c"

  while getopts ${optstring} arg; do
    case ${arg} in
    h)
      usage
      exit 0
      ;;
    p)
      echoinfo "-p supplied, using pre-built docker images."
      BUILD_DOCKER_IMAGES_FROM_SRC=0
      ;;
    r)
      REMOTE=1
      REMOTE_ADDR="$OPTARG"
      echoinfo "-r supplied, running experiments remotely at $REMOTE_ADDR."
      ;;
    g)
      DATA_GENERATOR_IPS="$OPTARG"
      echoinfo "-g supplied, using nodes \"$generators\" as data generators."
      ;;
    c)
      PRE_FLIGHT=1
      echoinfo "-c supplied, user has completed pre-flight checks."
      ;;
    :)
      echoerr "$0: Must supply an argument to -$OPTARG." >&2
      exit 1
      ;;
    ?)
      echoerr "Invalid option: -${OPTARG}."
      exit 2
      ;;
    esac
  done
}

parse_inputs $@

if [ "$PRE_FLIGHT" = "0" ]; then
  pre_flight_check
  exit 0
fi

if [ ! -d "./venv" ]; then
  echoinfo "Setting up python venv."
  python3 -m venv ./venv
  source venv/bin/activate
  pip3 install matplotlib numpy pandas oca confluent_kafka

else
  echoinfo "Activating existing python venv."
  source venv/bin/activate
fi

# PLAN ==================
# 2. Then, try to do the kubernetes deployments.
# Copy kube config from remote machine.
# 3. Then, try to do the build process
# 3. Then, SurfSara deployments.

if [ "$BUILD_DOCKER_IMAGES_FROM_SRC" == 1 ]; then
  # Clone repositories & build
  . 1_build_artifacts.sh
fi


if [ ! -d "./beam" ]; then
  echoinfo "Cloning Clonos' Beam implementation for NEXMARK experiments"
  git clone https://github.com/delftdata/beam
else
  echoinfo "Skipping git clone of beam because directory already present."
fi


if [ "$REMOTE" = "1" ]; then
  # Needed for helm to function
  kubectl apply -f ./kubernetes/rbac-config.yaml

  echoinfo "Creating Kubernetes service account."
  kubectl apply -f ./kubernetes/pubregcred.yaml
  kubectl patch serviceaccount default -p '{"imagePullSecrets": [{"name": "pubregcred"}]}'

  #TODO do remaining set-up of local state
fi

date=$(date +%Y-%m-%d_%H:%M)
path_prefix="./data/results-$date"
mkdir -p $path_prefix/images

. 2_run_experiments.sh $path_prefix
echoinfo "Experiments completed."

echoinfo "Generating experiment graphs in $path_prefix."
python3 generate_figures.py "$path_prefix" "$path_prefix/images"

#TODO compile paper with new images
cp $path_prefix/images/*.pdf ./paper_source/Figures
cd ./paper_source && make all
