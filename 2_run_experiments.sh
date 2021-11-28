# First runs all experiments for Flink, then Clonos.
# This means it first boots up an appropriate deployment using either local or remote deployment
# It resets the clusters as needed.
# Then it invokes functions to perform a single experiment.
# We do have the problem of needing to know the number of nodes... We could fix it to the max...
# We can also make that a parameter...

#Load functionality shared by all experiments
. experiments_shared_code.sh

# We use different numbers of events for different queries to ensure similar runtimes.
# For Overhead experiments
declare -A QUERY_TO_NUM_EVENTS
QUERY_TO_NUM_EVENTS[1]=100000000
QUERY_TO_NUM_EVENTS[2]=100000000
QUERY_TO_NUM_EVENTS[3]=100000000
QUERY_TO_NUM_EVENTS[4]=10000000
QUERY_TO_NUM_EVENTS[5]=10000000
QUERY_TO_NUM_EVENTS[6]=10000000
QUERY_TO_NUM_EVENTS[7]=10000000
QUERY_TO_NUM_EVENTS[8]=100000000
QUERY_TO_NUM_EVENTS[9]=10000000
QUERY_TO_NUM_EVENTS[11]=10000000
QUERY_TO_NUM_EVENTS[12]=10000000
QUERY_TO_NUM_EVENTS[13]=10000000
QUERY_TO_NUM_EVENTS[14]=10000000


# Throughput in failure experiments
declare -A QUERY_TO_THROUGHPUT
QUERY_TO_NUM_EVENTS[3]=500000
QUERY_TO_NUM_EVENTS[8]=500000 #TODO seems like this may be 1000000

# Kill Depth in failure experiments. We set these such that they kill stateful operators (such as full-history join)
declare -A QUERY_TO_KILL_DEPTH
QUERY_TO_NUM_EVENTS[3]=2
QUERY_TO_NUM_EVENTS[8]=1

path_prefix=$1

overhead_path="$path_prefix/nexmark_overhead"
echo -e "SYSTEM\tQUERY\tPARALLELISM\tDSD\tNUM_EVENTS\tTHROUGHPUT" >> $overhead_path

for system in "flink" "clonos"; do

  echo "================================================================================================================"
  echo "============================================ Starting $system =================================================="
  echo "================================================================================================================"

  if [ "$system" = "flink"]; then
    export SYSTEM_CONTAINER_IMG=$FLINK_IMG
  else
    export SYSTEM_CONTAINER_IMG=$CLONOS_IMG
  fi

  if [ "$REMOTE" = "0" ]; then
    docker-compose -f ./compose/docker-compose.yml up -d
  else
    TODO=1
  #TODO instakube deploy
  fi

  #TODO prepare cluster as needed for Flink/Clonos

  #TODO do necessary reconfiguration of beam runner
  #TODO run nexmark overhead experiments
  #git checkout overhead branch


  echo -e "\t\t\t======================= Starting Nexmark Overhead Experiments ==========================="
  cd ./beam && git checkout clonos-runner
  # Source nexmark testing scripts
  . ./2.1_nexmark_experiments.sh
  for query in 1 2 3 4 5 6 7 8 9 11 12 13 14 ; do
    num_events="${QUERY_TO_NUM_EVENTS[$query]}"
      if [ "$system" = "clonos" ] ; then
        #If the system is Clonos, run two configurations full DSD and one DSD
        for dsd in "-1" "1" ; do
          jobstr="$system;$query;$D_PARALLELISM_OVERHEAD;$D_CI;$num_events;$dsd;$D_PTI_CLONOS"
          start_nexmark_overhead_experiment $jobstr $overhead_path
        done
      elif [ "$system" = "flink" ] ; then
          jobstr="$system;$query;$D_PARALLELISM_OVERHEAD;$D_CI;$num_events;$D_DSD_FLINK;$D_PTI_FLINK"
          start_nexmark_overhead_experiment $jobstr $overhead_path
      fi
  done

  echo -e "\t\t\t======================= Starting Nexmark Failure Experiments ==========================="
  cd ./beam && git checkout clonos-runner-failure-experiments
  #TODO do necessary reconfiguration of beam runner
  #TODO run nexmark failure experiments
  #git checkout failure branch
  for query in 3 8 ; do
    path="$path_prefix/nexmark_failure/$system/q$query"
    throughput="${QUERY_TO_THROUGHPUT[$query]}"
    num_events=$(( throughput * FAILURE_TOTAL_EXPERIMENT_DURATION ))
    kill_depth="${QUERY_TO_KILL_DEPTH[$query]}"

    if [ "$system" = "clonos" ] ; then
      jobstr="$system;$query;$D_PARALLELISM_FAILURE;$D_CI;$num_events;$D_DSD_CLONOS_FAILURE;$D_PTI_CLONOS;$kill_depth"
    elif [ "$system" = "flink" ] ; then
      jobstr="$system;$query;$D_PARALLELISM_FAILURE;$D_CI;$num_events;$D_DSD_FLINK;$D_PTI_FLINK;$kill_depth"
    fi

    start_nexmark_failure_experiment $jobstr $path
  done

  echo -e "\t\t\t======================= Starting Synthetic Failure Experiments ==========================="
  #For synthetic failure experiments, we simply do two configurations (multiple and concurrent failures) using the default parameters.
  #See file below to find definitions of each parameter
  . ./2.2_synthetic_failure_experiments.sh
  for failure_type in "multiple" "concurrent"; do
    path="$path_prefix/synthetic_failure/$system/fail_$failure_type"
    jobstr="$system;$D_THR;$D_LTI;$D_WI;$D_DSD;$D_PTI;$failure_type;$D_KD;$D_CI;$D_SS;$D_AS;$D_KEYS;$D_P;$D_D;$D_SHFL;$D_O;$D_W_SIZE;$D_W_SLIDE;$D_ST;$D_TC;$D_GEN_TS;$D_GEN_RAND;$D_GEN_SER"
    start_synthetic_failure_experiment $path $jobstr
  done

done


