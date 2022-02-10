#!/bin/bash

PRE_FLIGHT=0

REMOTE=0
PROVISION=0
SCALE_DOWN=0

DATA_GENERATOR_IPS=""

BUILD_DOCKER_IMAGES_FROM_SRC=1

CLONOS_IMG="psylvan/clonos_repro_build"
FLINK_IMG="psylvan/flink_repro_build"

function usage() {
  echo "Clonos Reproducibility:"
  echo -e "\t -p \t\t\t - Uses [p]re-built images of Flink and Clonos. Skips building docker images from artifact source (They should be identical)."
  echo -e "\t -r \t\t\t - Run experiments [r]emotely on Kubernetes. ~/.kube/config needs to be set-up"
  echo -e "\t -g [semi-colon separated list of user@IP which can be ssh'ed into] \t\t - Uses the provided hosts as data-[g]enerators for synthetic tests."
  echo -e "\t\t\t\t\t\t Requires password-less SSH. Each host must have the kafka directory in their home. Most likely not needed."
  echo -e "\t -s [password] \t\t - Provision a cluster for experiments from [S]urfSara. Password must be requested to the authors. Will exit after provisioning."
  echo -e "\t -d \t\t\t - Scale [d]own experiments so they can be run on fewer resources. Edit experimental_parameters.sh for more control. "
  echo -e "\t -c \t\t\t - Confirms you have completed the pre-flight [c]hecks."
  echo -e "\t -h \t\t\t - shows [h]elp."
}

function pre_flight_check() {
  echo -e "Pre-flight check flag (-c) was not passed, please read the following:"
  echo -e "Dependencies:"
  echo -e "\t\t\t General: java8, python3, gradle 4<, pdflatex, bibtex"
  echo -e "\t\t\t If building containers from source (DEFAULT): git, maven 3.2.5"
  echo -e "\t\t\t If local experiments (DEFAULT): docker, docker-compose"
  echo -e "\t\t\t If remote experiments (-r): kubectl, helm"
  echo -e "Please install all required dependencies."
  echo -e ""
  echo -e "We have attempted to automate as much as possible, but one step is still required: 'docker login' "
  echo -e "\t This is needed because Docker now unfortunately limits image downloads. "
  echo -e "\t To ensure no problems, a Docker account with sufficient daily image pulls (https://www.docker.com/pricing) can be created as the free plan may hit its limits."
  echo -e "\t Once an account (free or not) is created, use 'docker login' on your local machine. "
  echo -e "\t Our scripts will use this identity to generate docker images (if -p is omitted) and to perform cluster image pulls (if -r is passed)."
  echo -e ""
  echo -e "Call this script again using the -c flag to certify you have completed the pre-flight check."
}

echoerr() {
  echo -e "ERROR: $@" 1>&2
  usage
}

echoinfo() { echo -e "INFO: $@"; }

function parse_inputs() {
  optstring=":hpdrs:g:c"

  while getopts ${optstring} arg; do
    case ${arg} in
    h)
      usage
      exit 0
      ;;
    p)
      BUILD_DOCKER_IMAGES_FROM_SRC=0
      echoinfo "-p supplied, using pre-built docker images."
      ;;
    d)
      SCALE_DOWN=1
      echoinfo "-d supplied, scaling down experiments."
      ;;
    r)
      REMOTE=1
      echoinfo "-r supplied, running experiments remotely."
      ;;
    g)
      DATA_GENERATOR_IPS="$OPTARG"
      echoinfo "-g supplied, using nodes \"$DATA_GENERATOR_IPS\" as data generators."
      ;;
    s)
      PROVISION=1
      REMOTE=1
      PASSWORD="$OPTARG"
      echoinfo "-s supplied, will provision cluster for experiments."
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
  pip3 install --upgrade pip >/dev/null 2>&1
  pip3 install wheel >/dev/null 2>&1
  pip3 install matplotlib numpy pandas confluent_kafka >/dev/null 2>&1
  #Cant install from pypi repositories as it contains old version which is broken
  pip3 install git+https://github.com/python-oca/python-oca >/dev/null 2>&1

else
  echoinfo "Activating existing python venv."
  source venv/bin/activate
fi

# Clone repositories & build
. 1_build_artifacts.sh

if [ ! -d "./beam" ]; then
  echoinfo "Cloning Clonos' Beam implementation for NEXMARK experiments"
  git clone https://github.com/delftdata/beam
else
  echoinfo "Skipping git clone of beam because directory already present."
fi

if [ "$PROVISION" = "1" ]; then
    echoinfo "Provisioning cluster from SurfSara. This can take up to 15 minutes."
    OUT=($(cd ./surf_sara_provision && python3 provision.py -pw $PASSWORD))
    IP=${OUT[0]}
    DATA_GENERATOR_IPS=${OUT[1]}
    echoinfo "Copying Kubeconfig to local computer."
    scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null ubuntu@$IP:~/.kube/config ~/.kube/config  >/dev/null 2>&1
    echoinfo "Setting up local storage on the cluster. This will also take a few minutes."
    sleep 60
    pushd ./kubernetes >/dev/null 2>&1
    python3 setup_local_storage.py
    popd >/dev/null 2>&1

    path_to_docker_config="$HOME/.docker/config.json"
    kubectl create secret generic pubregcred --from-file=.dockerconfigjson=$path_to_docker_config --type=kubernetes.io/dockerconfigjson >/dev/null 2>&1
    # Needed for helm to function
    kubectl apply -f ./kubernetes/rbac-config.yaml >/dev/null 2>&1

    echoinfo "Creating Kubernetes service account."
    kubectl patch serviceaccount default -p '{"imagePullSecrets": [{"name": "pubregcred"}]}' >/dev/null 2>&1

    echoinfo "Done. You can now ssh into the machine at ubuntu@$IP."
    echoinfo "You can launch experiments by doing the folowing:"
    echoinfo "\t 1. ssh ubuntu@$IP "
    echoinfo "\t 2. cd ClonosReproducibility"
    echoinfo "\t 3. git pull # Ensure  the VM has the latest version of the reproducibility scripts"
    echoinfo "\t 4. nohup ./0_workflow.sh -c -p -r -g \"$DATA_GENERATOR_IPS\" & # We use nohup to prevent hangups from SSH"
    echoinfo "\t 5. tail -f nohup.out # Follow the output of the script"
    echoinfo "\t You may omit -p in order to build new Clonos and Flink docker images from scratch, but this will be wasteful of the remaining cluster resources. Furthermore, the images will be identical."
    echoinfo "Exiting..."
    exit
fi

if [ "$REMOTE" = "1" ]; then
  # At this point we can go ahead and set-up the infrastructure (Kafka and Hadoop) if running on Kubernetes.
  helm install hadoop ./kubernetes/charts/hadoop >/dev/null 2>&1
  helm install confluent ./kubernetes/charts/cp-helm-charts >/dev/null 2>&1

  echoinfo "Setting up HDFS and Kafka for experiments ahead of time."
fi

date=$(date +%Y-%m-%d_%H:%M)
path_prefix="./data/results-$date"
mkdir -p $path_prefix/images

. 2_run_experiments.sh $path_prefix
echoinfo "Experiments completed."

echoinfo "Generating experiment graphs in $path_prefix."
python3 generate_figures.py "$path_prefix" "$path_prefix/images"

cp $path_prefix/images/*.pdf ./paper_source/Figures
cd ./paper_source && make all
echoinfo "Finished, you can find the recompiled paper in ./paper_source/hastreaming.pdf. Experimental results are at $path_prefix and graphs are at $path_prefix/images."
