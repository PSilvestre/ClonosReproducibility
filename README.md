# Clonos SIGMOD'21 Reproducibility

<img src="https://delftdata.github.io/clonos-web/clonos-web-logo.png" width=50% height=50%>

## Basic Identifiers
* **Title**: "Clonos: Consistent Causal Recovery for Highly-Available Streaming Dataflows"
* **Authors**: Pedro F. Silvestre, Marios Fragkoulis, Diomidis Spinellis, Asterios Katsifodimos
* **Paper ID**: rdm517
* **DOI**: 10.1145/3448016.3457320
* **ACM Digital Library**: [Link](https://dl.acm.org/doi/abs/10.1145/3448016.3457320)
* **Reproducibility Repository**: https://github.com/PSilvestre/ClonosReproducibility

This PDF is also the README.md of the above Reproducibility Repository. It may be more readable (e.g syntax highlighting) on GitHub.

## Introduction

This is a difficult paper to reproduce due to the sheer number of dependencies and distributed components required (Stream processor, HDFS, Kafka, Zookeeper, Data Stream Generators and more).
To ease this, we execute our experiments on a virtualized environment: Docker or Kubernetes.
* Local testing: much simpler, but less accurate to our experiments. Uses docker-compose on a large scale-up machine.
* Remote testing: requires a Kubernetes cluster with certain specifications. We have included scripts to provision such a cluster, but the cluster password must be requested.

As requested, the scripts should handle everything:
* Downloading the source code of the systems
* Compiling the systems
* Producing Docker images of the systems
* Provisioning a cluster to execute experiments on
* Installing Kubernetes on said cluster
* Deploying the infrastructure components on Kubernetes (HDFS, Kafka, Zookeeper, Flink and Clonos)
* Executing the experiments and collecting results
* Generating Figures
* Recompiling the paper

To speed up this process we also provide pre-built docker images, which will be identical to the resulting build from source.

We provide the requested README format below.

## Requested README Format

### A) Source code info

:warning: *There is no need to clone any repository other than the reproducibility one. The reproducibility scripts should perform all the heavy lifting.*

**Repositories:**
* [Clonos Source Code](https://github.com/delftdata/Clonos) - The source code of the Clonos System. Branch 'flink1.7' contains the version of Flink we tested against.

**Programming Languages:**
* Main System: Java
* Workloads: Java (BEAM NEXMark), Scala (Synthetic)
* Testing scripts: Bash (orchestration), Python (Figures, latency and throughput measurers)

**Additional Programming Language info:** Java8

**Compiler Info:** openjdk version "1.8.0_292"

**Packages/Libraries Needed:** To build the system, maven will download all dependencies automatically. 
**Dependencies** (See below for a breakdown): java8, python3 (with pip and virtualenv), gradle 4<, make, pdflatex, bibtex, git, maven 3.2.5, docker, docker-compose, kubectl, helm

**Breakdown:**
* General: java8, python3 (with pip and virtualenv), gradle 4<, make, pdflatex, bibtex
* If building containers from source (DEFAULT): git, maven 3.2.5
* If local experiments (DEFAULT): docker, docker-compose
* If remote experiments (-r): kubectl, helm

### B) Datasets info

:warning: *There is no need to clone any repository other than the reproducibility one. The reproducibility scripts should perform all the heavy lifting.*

**Data generators Repository:**
* [BEAM w\ ClonosRunner](https://github.com/delftdata/beam) - Used in the NEXMark experiments. Branches clonos-runner and clonos-runner-failure-experiments are used respectively in overhead and failure experiments.
* [Synthetic workload](https://github.com/delftdata/flink-test-scripts) - Contains the synthetic workload source code and our custom measuring (throughput and latency) scripts.

### C) Hardware Info

Our experiments are executed on 2 layers of virtualization. At the bottom we represent bare-metal:
1. Docker containers (managed by Kubernetes)
2. HPCCloud VirtualMachines
3. SurfSara cluster bare-metal nodes.

We will work from bottom to top, describing our deployments for each layer.

#### Bare-Metal
At the bare-metal layer, we execute on SurfSara gold_6130 nodes. Their information is as follows:

* C1) Processor: [Intel® Xeon® Gold 6130 Processor](https://ark.intel.com/content/www/us/en/ark/products/120492/intel-xeon-gold-6130-processor-22m-cache-2-10-ghz.html)
* C2) Caches: L1: 16 x 32 KB 8-way set associative instruction caches + 16 x 32 KB 8-way set associative data caches , L2: 16 x 1 MB 16-way set associative caches, L3: 22 MB non-inclusive shared cache
* C3) Memory: 96 GB UPI 10.4 GT/s
* C4) Secondary Storage: 3.2 TB local SSD disk 
* C5) Network: 10 Gbit/s ethernet

Additional hardware information about the SurfSara cluster may be found
[here](https://servicedesk.surfsara.nl/wiki/display/WIKI/HPC+Cloud+documentation) and [here](https://servicedesk.surfsara.nl/wiki/display/WIKI/Lisa+hardware+and+file+systems).

#### Virtual Machines

On top of this Hardware we request the following Virtual Machines
* 1 Coordinator Node (hosts Kubernetes Coordinator)
  * 8vCPU
  * 16GB memory
  * 50GB Disk
* 6 Follower Nodes (Kubernetes Followers)
  * 40vCPU
  * 60GB memory
  * 100GB Disk
* 2 Generator Nodes (Data Generators for Synthetic Failure Experiments)
  * 4vCPU
  * 4GB memory
  * 5GB Disk

#### Containers

On top of the VMs we set-up Kubernetes and launch a number of components.
Note that 500m CPU indicates 1/2 of a CPU:
* Zookeeper: 3 nodes, 500m CPU, 512Mi memory, 5Gi Persistent Volume
* Kafka: 5 nodes, 2000m CPU, 4000Mi memory, 50Gi Persistent Volume
* HDFS: 
  * 1 Namenode, 4000m CPU, 4000Mi memory, 50Gi Persistent Volume
  * 3 Datanode, 3000m CPU, 8000Mi memory, 50Gi Persistent Volume
* Flink:
  * 1 JobManager, 8000m CPU, 8192Mi memory
  * 150 TaskManager, 2000m CPU, 2000Mi memory, 5Gi Persistent Volume

The ./kubernetes/charts directory contains the deployment manifests, which are a complete source-of-truth.


### D) Experimentation Info

Before starting, create a docker account and execute ```docker login```. This is required for building a pushing
docker images. It will also be used as the identity for image pulls performed by the cluster.

The main script is ```0_workflow.sh```. By default it will execute experiments locally, using newly built docker images. 
It receives a number of parameters which can change its behaviour:
| Flag | Parameter             | Description                                                                           |
| ---- | --------------------- | ------------------------------------------------------------------------------------- |
| -p | - | Uses [p]re-built images of Flink and Clonos. Skips building docker images from artifact source.             |
| -r | - | Run experiments [r]emotely on Kubernetes. ~/.kube/config needs to be set-up (it is set-up by -s)            |
| -g | semi-colon;separated;list;of;user@IP | Uses the provided hosts as data-[g]enerators for synthetic tests. Requires password-less SSH. |
| -s  | password | Provision a cluster for experiments from [S]urfSara. Password must be requested to the authors. Will exit after provisioning. |
| -d || - | Scale [d]own experiments (e.g. parallelism) so they can be run on fewer resources. Edit experimental_parameters.sh for more control. |
| -c | - | Confirms you have read and completed the pre-flight [c]hecks. |
| -h | - | Shows [h]elp |

If performing remote experiments, email the authors requesting the password for the delta account in the SurfSara cluster.
Alternatively, we can provision the cluster for you ourselves on-demand. Pedro may be reached at pmf<lastName>@gmail.com.
If necessary, we will be available to guide you through the reproduction of experiments.

We will now show a series of scenarios and how the script may be used.

#### Local experiments with pre-built images

:warning: For local experiments using the -d (scale-down) flag is highly recommended.

```bash
git clone https://github.com/PSilvestre/ClonosReproducibility
cd ./ClonosReproducibility

# -p specifies prebuilt, omission of -r assumes local.
./0_workflow.sh -p -c -d
```

#### Local experiments with images built from source

:warning: For local experiments using the -d (scale-down) flag is highly recommended.

```bash
docker login
git clone https://github.com/PSilvestre/ClonosReproducibility
cd ./ClonosReproducibility

# omission of -p assumes build from source, omission of -r assumes local.
./0_workflow.sh -c -d
```

#### Provision a cluster, execute remote experiments using pre-built images
```bash
docker login
git clone https://github.com/PSilvestre/ClonosReproducibility
cd ./ClonosReproducibility
./0_workflow.sh -c -p -s <password> 
```
Once finished the script will print a message similar to this, which you should follow:

```
Done. You can now ssh into the machine at ubuntu@$IP.
You can launch experiments by doing the folowing:
    1. ssh ubuntu@$IP
    2. cd ClonosProvisioning
    3. git pull # Ensure latest version
    4. nohup ./0_workflow.sh -c -p -r -g "$DATA_GENERATOR_IPS" & #use nohup to prevent hangups
    5. tail -f nohup.out
```

#### Provision a cluster, execute remote experiments with images built from source
To save on cluster resource we will first generate the docker images, then provision the cluster and then execute.

```bash
docker login
git clone https://github.com/PSilvestre/ClonosReproducibility
cd ./ClonosReproducibility

# This will build the docker images, push them to the docker hub and print their names. Record these names.
BUILD_DOCKER_IMAGES_FROM_SRC=1 &&  ./1_build_artifacts.sh

#Once finished, provision the cluster.
./0_workflow.sh -c -p -s <password> 
```
Once finished the script will print a message similar to this:
```
Done. You can now ssh into the machine at ubuntu@$IP.
You can launch experiments by doing the folowing:
    1. ssh ubuntu@$IP
    2. cd ClonosProvisioning
    3. git pull # Ensure latest version
    4. nohup ./0_workflow.sh -c -p -r -g "$DATA_GENERATOR_IPS" &
    5. tail -f nohup.out
```

Follow these instructions, but before executing the 0_workflow.sh script, edit the variables FLINK_IMG and CLONOS_IMG
at the top of 0_workflow.sh to use your docker image versions.

#### Executing remote experiments from local computer, with images built from source
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

### Other Notes

Several parameters can be easily changed on all experiments. 
Experiments are specified in 2_run_experiments.sh as a configuration string such as this:
```
jobstr="$system;$query;$par;$D_CI;$throughput;$D_DSD_CLONOS_FAILURE;$D_PTI_CLONOS;$kill_depth"
```
The second parameter specifies the Nexmark query to use, while the third parameter specifies the parallelism to use and so on...

We decided to provide the synthetic workload as pre-built jars to ease automation efforts. 
These are the 'synthetic_workload_clonos.jar' and 'synthetic_workload_flink.jar'
The same could not be achieved for the beam project, and as such the dependency on Gradle remains.

We thank the reproducibility reviewers for their efforts, and hope that you appreciate ours in attempting to simplify the complexity of these experiments.
Such large scale experiments can be flaky and there may be the need to rerun certain experiments/stitch together results.
The authors are prepared to support the reproducibility reviewers in their work. Again, Pedro may be reached at pmf<lastName>@gmail.com.