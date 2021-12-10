# Clonos (SIGMOD 2021) Reproducibility (ID: rdm517)

This repository contains information on how to reproduce the experiments in the SIGMOD'21 paper 
"Clonos: Consistent Causal Recovery for Highly-Available Streaming Dataflows". DOI: 10.1145/3448016.3457320, ID: rdm517

Our original experiments were executed on the private SurfSara cluster.
This is a difficult paper to reproduce due to the number of distributed components required (Stream processor, HDFS, Kafka, Zookeeper, Data Stream Generators and more).
To ease this, we execute our experiments on a virtualized environment on top of Kubernetes.

We have attempted to make it as easy as possible to reproduce. Two options are available:
* Local testing: much simpler, but less accurate to our experiments. Uses docker-compose on a large scale-up machine.
* Remote testing: requires a Kubernetes cluster with certain specifications. We have included scripts to provision such a cluster, but the cluster password must be requested.

Our scripts can also automatically pull the Clonos repository, build it using maven and package it into a docker image if desired.
To speed up this process we also provide pre-built images, which will be identical to the resulting build.

The main script is ```0_workflow.sh``` and it receives a number of parameters:
| Flag | Parameter             | Description                                                                           |
| ---- | --------------------- | ------------------------------------------------------------------------------------- |
| -p | - | Uses [p]re-built images of Flink and Clonos. Skips building docker images from artifact source.             |
| -r | - | Run experiments [r]emotely on Kubernetes. ~/.kube/config needs to be set-up (it is set-up by -s)            |
| -g | semi-colon;separated;list;of;user@IP | Uses the provided hosts as data-[g]enerators for synthetic tests. Requires password-less SSH. |
| -s  | password | Provision a cluster for experiments from [S]urfSara. Password must be requested to the authors. Will exit after provisioning. |
| -c | - | Confirms you have read and completed the pre-flight [c]hecks. |
| -h | - | Shows [h]elp |

## Dependencies

* General: java8, python3, gradle 4<, make, pdflatex, bibtex
* If building containers from source (DEFAULT): git, maven 3.2.5
* If local experiments (DEFAULT): docker, docker-compose
* If remote experiments (-r): kubectl, helm

## Instructions

Before starting, create a docker account and execute ```docker login```. This is required for building a pushing
docker images. It will also be used as the identity for image pulls performed by the cluster.

If performing remote experiments, email the authors requesting the password for the delta account in the SurfSara cluster.
Alternatively, we can provision the cluster ourselves on-demand. Pedro may be reached at pmf<last-name> at gmail.com.

We will now show a series of scenarios and how the script may be used.

### Local experiments with pre-built images
```bash
git clone https://github.com/PSilvestre/ClonosReproducibility
cd ./ClonosReproducibility
# You will probably want to lower the parallelism by editing the associative array EXPERIMENT_TO_PARALLELISM in 2_run_experiments.sh
# It is unlikely that a parallelism of 25 will fit in any one server.
./0_workflow.sh -p -c
# -p specifies prebuilt, omission of -r assumes local.
```

### Local experiments with images built from source
```bash
docker login
git clone https://github.com/PSilvestre/ClonosReproducibility
cd ./ClonosReproducibility
# You will probably want to lower the parallelism by editing the associative array EXPERIMENT_TO_PARALLELISM in 2_run_experiments.sh
# It is unlikely that a parallelism of 25 will fit in any one server.
./0_workflow.sh -c
# omission of -p assumes build from source, omission of -r assumes local.
```

### Provision a cluster, execute remote experiments using pre-built images
```bash
docker login
git clone https://github.com/PSilvestre/ClonosReproducibility
cd ./ClonosReproducibility
./0_workflow.sh -c -p -s <password> 
```
Once finished the script will print a message similar to this:

```
Done. You can now ssh into the machine at ubuntu@$IP.
You can launch experiments by doing the folowing:
    1. ssh ubuntu@$IP
    2. cd ClonosProvisioning
    3. ./0_workflow.sh -c -p -r -g $DATA_GENERATOR_IPS
```

### Provision a cluster, execute remote experiments with images built from source
To save on cluster resource we will first generate the docker images, then provision the cluster and then execute.

```bash
docker login
git clone https://github.com/PSilvestre/ClonosReproducibility
cd ./ClonosReproducibility
# This will build the docker images, push them to the docker hub and print their names. Record these names.
./1_build_artifacts.sh

#Once finished, provision the cluster.
./0_workflow.sh -c -p -s <password> 
```
Once finished the script will print a message similar to this:
```
Done. You can now ssh into the machine at ubuntu@$IP.
You can launch experiments by doing the folowing:
    1. ssh ubuntu@$IP
    2. cd ClonosProvisioning
    3. ./0_workflow.sh -c -p -r -g $DATA_GENERATOR_IPS
```

Follow these instructions, but before executing the 0_workflow.sh script, edit the variables FLINK_IMG and CLONOS_IMG
at the top of 0_workflow.sh to use your docker image versions.

### Executing remote experiments from local computer, with images built from source
You can also avoid SSH'ing into the remote host, because experiments can be launched remotely.
However, these are likely to yield worse results and take even longer to execute.
```bash
docker login
git clone https://github.com/PSilvestre/ClonosReproducibility
cd ./ClonosReproducibility

# Provision the cluster
./0_workflow.sh -c -p -s <password> 

# Execute experiments. This will first build the images, then use kubectl to manage them. 
# This will waste some cluster time, which is undesirable.
./0_workflow.sh -c -r
```

## Other repositories

* Clonos: https://github.com/delftdata/Clonos
* Beam w\ ClonosRunner: https://github.com/delftdata/beam (Used in NEXMark experiments)
* Synthetic workload: https://github.com/delftdata/flink-test-scripts (Used in synthetic experiments)

We decided to provide the synthetic workload as pre-built jars to ease automation efforts. These are the 'synthetic_workload_clonos.jar' and 'synthetic_workload_flink.jar'

## Hardware Information
Hardware information about the SurfSara cluster may be found 
[here](https://servicedesk.surfsara.nl/wiki/display/WIKI/HPC+Cloud+documentation) and [here](https://servicedesk.surfsara.nl/wiki/display/WIKI/Lisa+hardware+and+file+systems).