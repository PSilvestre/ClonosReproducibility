#!/bin/bash

PRE_FLIGHT=0

REMOTE=0
REMOTE_ADDR=""

DATA_GENERATOR_IPS=""

BUILD_DOCKER_IMAGES_FROM_SRC=0

CLONOS_IMG="psylvan/clonos"
FLINK_IMG="psylvan/flink"

function usage() {
  echo "This script will by default run experiments locally using docker-compose and our prebuilt docker images, for ease of use."
  echo "To configure these behaviours:"
  echo -e "\t -b \t\t\t - [b]uilds docker images from artifact source and uses them in tests."
  echo -e "\t -r [user@ip] \t\t - Run experiments remotely on Kubernetes cluster whose master node is provided. Need passwordless ssh into the machine."
  echo -e "\t -g [semi-colon separated list of user@IP which can be ssh'ed into] \t\t - Uses the provided hosts as data-generators for synthetic tests."
  echo -e "\t\t\t\t\t\t Uses password-less SSH. Each host must have the kafka directory in their home. Most likely not needed."
  echo -e "\t -c \t\t\t - Confirms you have completed the pre-flight checks."
  echo -e "\t -h \t\t\t - shows [h]elp."
}

function pre_flight_check() {
  echo "Pre-flight check flag (-c) was not passed, please read the following:"
  echo "Dependencies:"
  echo "\t\t\t General: java8, python3.8, gradle 7"
  echo "\t\t\t If building containers from source (-b): git, maven3"
  echo "\t\t\t If local experiments (DEFAULT): docker, docker-compose"
  echo "\t\t\t If remote experiments (-r): kubectl, helm"
  echo ""
  echo "Testing distributed data-intensive systems at scale is complicated. We have tried to automate it as much as possible, but some work is still required if using Kubernetes (-r option):"
  echo "\t\t\t Ensure you have a deployed cluster with enough capacity and copied the kube config to your local machine (~/.kube/config)."
  echo "\t\t\t Docker now unfortunately limits image downloads. To ensure no problems, a Docker account with sufficient daily image pulls (https://www.docker.com/pricing) can be created as the free plan may hit its limits."
  echo "\t\t\t Once an account (free or not) is created, create a Kubernetes service account so the cluster uses this identity to pull images:"
  echo "\t\t\t\t\t\t 1. docker login"
  echo "\t\t\t\t\t\t 2. kubectl create secret generic pubregcred --from-file=.dockerconfigjson=<path/to/.docker/config.json> --type=kubernetes.io/dockerconfigjson"
  echo "\t\t\t\t\t\t 3. Place the resulting file in the 'kubernetes' directory of this project"
  echo ""
  echo "Call this script again using the -c flag to certify you have completed the pre-flight check."
}

echoerr() { echo "ERROR: $@" 1>&2; usage; }

echoinfo() { echo "INFO: $@"; }

function parse_inputs() {
  optstring=":hbr:g:c"

  while getopts ${optstring} arg; do
    case ${arg} in
    h)
      usage
      exit 0
      ;;
    b)
      echoinfo "-b supplied, building docker images from source."
      BUILD_DOCKER_IMAGES=1
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

if [ "$PRE_FLIGHT" = "0" ] ; then
  pre_flight_check
  exit 0
fi


if [ ! -d "./venv" ]; then

  echoinfo "Setting up python venv."
  python3 -m venv ./venv
  source venv/bin/activate
  pip3 install matplotlib numpy pandas oca confluent_kafka

else
  source venv/bin/activate
fi

# PLAN ==================
# 2. Then, try to do the kubernetes deployments.
  # Copy kube config from remote machine.
# 3. Then, try to do the build process
# 3. Then, SurfSara deployments.


#TODO check if this needs to be here
git clone https://github.com/delftdata/beam

if [ "$BUILD_DOCKER_IMAGES_FROM_SRC" == 1 ]; then

  #BEAMJARs: beam-runners-clonos-1.7-2.20.0-SNAPSHOT.jar
  #BEAMJARs: beam-runners-flink-1.7-2.20.0-SNAPSHOT.jar
  #BEAMJARs: beam-sdks-java-nexmark-2.20.0-SNAPSHOT.jar
  # Clone repositories & build
  . 1_download_artifacts.sh

  #TODO CLONOS_IMG=call_build_func
  #TODO FLINK_IMG=call_build_func
fi

if [ "$REMOTE" = "1" ] ; then
  # Needed for helm to function
  kubectl apply -f ./kubernetes/rbac-config.yaml

  echoinfo "Creating Kubernetes service account."
  kubectl apply -f ./kubernetes/pubregcred.yaml
  kubectl patch serviceaccount default -p '{"imagePullSecrets": [{"name": "pubregcred"}]}'
fi

date=$(date +%Y-%m-%d_%H:%M)
path_prefix="./data/results-$date"

. 2_run_experiments.sh $path_prefix
echoinfo "Experiments completed."

echoinfo "Generating experiment graphs in $path_prefix."
mkdir -p $path_prefix/images
python3 generate_figures.py "$path_prefix" "$path_prefix/images"

#TODO compile paper with new images
cp $path_prefix/images/*.pdf ./paper_source/Figures
cd ./paper_source && make all