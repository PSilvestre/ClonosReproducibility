#Load functionality shared by all experiments
. experiments_shared_code.sh

# We use different numbers of events for different queries to ensure similar runtimes.
# For Overhead experiments
declare -A QUERY_TO_NUM_EVENTS
#QUERY_TO_NUM_EVENTS[1]=100000000
#QUERY_TO_NUM_EVENTS[2]=100000000
#QUERY_TO_NUM_EVENTS[3]=100000000
#QUERY_TO_NUM_EVENTS[4]=10000000
#QUERY_TO_NUM_EVENTS[5]=10000000
#QUERY_TO_NUM_EVENTS[6]=10000000
#QUERY_TO_NUM_EVENTS[7]=10000000
#QUERY_TO_NUM_EVENTS[8]=100000000
#QUERY_TO_NUM_EVENTS[9]=10000000
#QUERY_TO_NUM_EVENTS[11]=10000000
#QUERY_TO_NUM_EVENTS[12]=10000000
#QUERY_TO_NUM_EVENTS[13]=10000000
#QUERY_TO_NUM_EVENTS[14]=10000000

QUERY_TO_NUM_EVENTS[1]=1000000
QUERY_TO_NUM_EVENTS[2]=1000000
QUERY_TO_NUM_EVENTS[3]=1000000
QUERY_TO_NUM_EVENTS[4]=100000
QUERY_TO_NUM_EVENTS[5]=100000
QUERY_TO_NUM_EVENTS[6]=100000
QUERY_TO_NUM_EVENTS[7]=100000
QUERY_TO_NUM_EVENTS[8]=100000
QUERY_TO_NUM_EVENTS[9]=100000
QUERY_TO_NUM_EVENTS[11]=100000
QUERY_TO_NUM_EVENTS[12]=100000
QUERY_TO_NUM_EVENTS[13]=100000
QUERY_TO_NUM_EVENTS[14]=100000
# Throughput in failure experiments
declare -A QUERY_TO_THROUGHPUT
QUERY_TO_THROUGHPUT[3]=50000
QUERY_TO_THROUGHPUT[8]=50000

# Kill Depth in failure experiments. We set these such that they kill stateful operators (such as full-history join)
declare -A QUERY_TO_KILL_DEPTH
QUERY_TO_KILL_DEPTH[3]=2
QUERY_TO_KILL_DEPTH[8]=1

declare -A EXPERIMENT_TO_PARALLELISM
#EXPERIMENT_TO_PARALLELISM["OVERHEAD"]=25
#EXPERIMENT_TO_PARALLELISM["SYNTH_MULTIPLE"]=5
#EXPERIMENT_TO_PARALLELISM["SYNTH_CONCURRENT"]=5
#EXPERIMENT_TO_PARALLELISM["NEXMARK_Q3"]=5
#EXPERIMENT_TO_PARALLELISM["NEXMARK_Q8"]=5
EXPERIMENT_TO_PARALLELISM["OVERHEAD"]=2
EXPERIMENT_TO_PARALLELISM["SYNTH_MULTIPLE"]=2
EXPERIMENT_TO_PARALLELISM["SYNTH_CONCURRENT"]=2
EXPERIMENT_TO_PARALLELISM["NEXMARK_Q3"]=2
EXPERIMENT_TO_PARALLELISM["NEXMARK_Q8"]=2

declare -A SYSTEM_TO_FAILOVER_STRATEGY
SYSTEM_TO_FAILOVER_STRATEGY["flink"]="full"
SYSTEM_TO_FAILOVER_STRATEGY["clonos"]="standbytask"

path_prefix=$1

overhead_path="$path_prefix/nexmark_overhead"
echo -e "SYSTEM\tQUERY\tPARALLELISM\tDSD\tNUM_EVENTS\tTHROUGHPUT" >>$overhead_path

for system in  "clonos" "flink"; do
  echo "================================= Starting $system experiments ======================================="

  if [ "$system" = "flink" ]; then
    export SYSTEM_CONTAINER_IMG=$FLINK_IMG
  else
    export SYSTEM_CONTAINER_IMG=$CLONOS_IMG
  fi

  echoinfo "Bringing up needed infrastructure..."
  max_par=$(echo "${EXPERIMENT_TO_PARALLELISM[@]}" | tr " " "\n" | sort | tail -n1)
  NUM_TASKMANAGERS_REQUIRED=$(( max_par * 6 * 2 )) # MAX_PAR * MAX_DEPTH * 2 (standby tasks) #TODO times 2 again cause of publisher and publisher standby?
  if [ "$REMOTE" = "0" ]; then
    strategy=${SYSTEM_TO_FAILOVER_STRATEGY[$system]}
    sed -i "s/jobmanager.execution.failover-strategy:.*/jobmanager.execution.failover-strategy: $strategy/g" ./compose/flink-conf.yaml
  else
    TODO=1
  #TODO instakube deploy
  fi

  echo -e "----------------------------- Starting Nexmark Overhead Experiments -------------------------------"
  $(cd ./beam && git checkout clonos-runner &> /dev/null)

  # Source nexmark testing scripts
  . ./2.1_nexmark_experiments.sh
  for query in 1 2 3 4 5 6 7 8 9 11 12 13 14; do
    num_events=${QUERY_TO_NUM_EVENTS[$query]}
    par=${EXPERIMENT_TO_PARALLELISM["OVERHEAD"]}
    if [ "$system" = "clonos" ]; then
      #If the system is Clonos, run two configurations full DSD and one DSD
      for dsd in "-1" "1"; do
        echoinfo "Starting configuration: SYS:$system;Q:$query;PAR:$par;CI:$D_CI;NE:$num_events;DSD:$dsd;PTI:$D_PTI_CLONOS"
        jobstr="$system;$query;$par;$D_CI;$num_events;$dsd;$D_PTI_CLONOS"
        reset_flink_cluster
        clear_kafka_topics $par
        start_nexmark_overhead_experiment $jobstr $overhead_path
      done
    elif [ "$system" = "flink" ]; then
      echoinfo "Starting configuration: SYS:$system;Q:$query;PAR:$par;CI:$D_CI;NE:$num_events;DSD:$D_DSD_FLINK;PTI:$D_PTI_FLINK"
      jobstr="$system;$query;$par;$D_CI;$num_events;$D_DSD_FLINK;$D_PTI_FLINK"
      reset_flink_cluster
      clear_kafka_topics $par
      start_nexmark_overhead_experiment $jobstr $overhead_path
    fi
  done

  echo -e "----------------------------- Starting Nexmark Failure Experiments --------------------------------"
  $(cd ./beam && git checkout clonos-runner-failure-experiments > /dev/null 2>&1)
  for query in 3 8; do
    par="${EXPERIMENT_TO_PARALLELISM["NEXMARK_Q$query"]}"
    path="$path_prefix/nexmark_failure/$system/q$query"
    throughput="${QUERY_TO_THROUGHPUT[$query]}"
    num_events=$((throughput * FAILURE_TOTAL_EXPERIMENT_DURATION))
    kill_depth="${QUERY_TO_KILL_DEPTH[$query]}"

    if [ "$system" = "clonos" ]; then
      echoinfo "Starting configuration: SYS:$system;Q:$query;PAR:$par;CI:$D_CI;NE:$num_events;DSD:$D_DSD_CLONOS_FAILURE;PTI:$D_PTI_CLONOS;KD:$kill_depth"
      jobstr="$system;$query;$par;$D_CI;$num_events;$D_DSD_CLONOS_FAILURE;$D_PTI_CLONOS;$kill_depth"
    elif [ "$system" = "flink" ]; then
      echoinfo "Starting configuration: SYS:$system;Q:$query;PAR:$par;CI:$D_CI;NE:$num_events;DSD:$D_DSD_FLINK;PTI:$D_PTI_FLINK;KD:$kill_depth"
      jobstr="$system;$query;$par;$D_CI;$num_events;$D_DSD_FLINK;$D_PTI_FLINK;$kill_depth"
    fi

    reset_flink_cluster
    clear_kafka_topics $par

    start_nexmark_failure_experiment $jobstr $path
  done

  echo -e "---------------------------- Starting Synthetic Failure Experiments -------------------------------"
  #For synthetic failure experiments, we simply do two configurations (multiple and concurrent failures) using the default parameters.
  #See file below to find definitions of each parameter
  . ./2.2_synthetic_failure_experiments.sh
  for failure_type in "multiple" "concurrent"; do
    par="${EXPERIMENT_TO_PARALLELISM["SYNTH_${failure_type^^}"]}"
    path="$path_prefix/synthetic_failure/$system/fail_$failure_type"
    jobstr="$system;$D_THR;$D_LTI;$D_WI;$D_DSD;$D_PTI;$failure_type;$D_KD;$D_CI;$D_SS;$D_AS;$D_KEYS;$par;$D_D;$D_SHFL;$D_O;$D_W_SIZE;$D_W_SLIDE;$D_ST;$D_TC;$D_GEN_TS;$D_GEN_RAND;$D_GEN_SER"

    echoinfo "Starting configuration: FAIL_TYPE: $failure_type"
    reset_flink_cluster
    clear_kafka_topics $par
    start_synthetic_failure_experiment $path $jobstr
  done

done
