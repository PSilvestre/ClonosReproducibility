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
QUERY_TO_THROUGHPUT[3]=50000
QUERY_TO_THROUGHPUT[8]=50000

# Kill Depth in failure experiments. We set these such that they kill stateful operators (such as join)
declare -A QUERY_TO_KILL_DEPTH
QUERY_TO_KILL_DEPTH[3]=2
QUERY_TO_KILL_DEPTH[8]=1

declare -A EXPERIMENT_TO_PARALLELISM
EXPERIMENT_TO_PARALLELISM["OVERHEAD"]=25
EXPERIMENT_TO_PARALLELISM["SYNTH_MULTIPLE"]=5
EXPERIMENT_TO_PARALLELISM["SYNTH_CONCURRENT"]=5
EXPERIMENT_TO_PARALLELISM["NEXMARK_Q3"]=5
EXPERIMENT_TO_PARALLELISM["NEXMARK_Q8"]=5

path_prefix=$1

overhead_path="$path_prefix/nexmark_overhead"
echo -e "SYSTEM\tQUERY\tPARALLELISM\tDSD\tNUM_EVENTS\tTHROUGHPUT" >>$overhead_path

max_par=$(echo "${EXPERIMENT_TO_PARALLELISM[@]}" | tr " " "\n" | sort | tail -n1)
NUM_TASKMANAGERS_REQUIRED=$((max_par * 6 * 2)) # MAX_PAR * MAX_DEPTH * 2 (standby tasks)


for system in "flink" "clonos"; do
  set_failover_strategy $system
  # Source nexmark testing scripts
  . ./2.1_nexmark_experiments.sh

  echo -e "----------------------------- Starting Nexmark Overhead Experiments -------------------------------"
  change_beam_branch "clonos-runner"
  set_number_of_standbys 0
  set_heartbeat 20000 200000 #Reduces flakyness of tests because no failures should happen (No false positive failure detections).

  redeploy_flink_cluster $system

  for query in 1 2 3 4 5 6 7 8 9 11 12 13 14; do
    num_events=${QUERY_TO_NUM_EVENTS[$query]}
    par=${EXPERIMENT_TO_PARALLELISM["OVERHEAD"]}
    if [ "$system" = "clonos" ]; then
      #If the system is Clonos, run two configurations full DSD and one DSD
      for dsd in "-1" "1"; do
        reset_flink_cluster $system
        clear_kafka_topics $par
        echoinfo "Starting configuration: SYS:$system;Q:$query;PAR:$par;CI:$D_CI;NE:$num_events;DSD:$dsd;PTI:$D_PTI_CLONOS"
        jobstr="$system;$query;$par;$D_CI;$num_events;$dsd;$D_PTI_CLONOS"
        start_nexmark_overhead_experiment $jobstr $overhead_path
      done
    elif [ "$system" = "flink" ]; then
      reset_flink_cluster $system
      clear_kafka_topics $par
      echoinfo "Starting configuration: SYS:$system;Q:$query;PAR:$par;CI:$D_CI;NE:$num_events;DSD:$D_DSD_FLINK;PTI:$D_PTI_FLINK"
      jobstr="$system;$query;$par;$D_CI;$num_events;$D_DSD_FLINK;$D_PTI_FLINK"
      start_nexmark_overhead_experiment $jobstr $overhead_path
    fi
  done

  echo -e "----------------------------- Starting Nexmark Failure Experiments --------------------------------"
  change_beam_branch "clonos-runner-failure-experiments"
  set_number_of_standbys 1
  set_heartbeat 4000 6000
  redeploy_flink_cluster $system
  reset_flink_cluster $system
  clear_kafka_topics 1

  echoinfo "Performing an initial experiment which is going to be DISCARDED. This ensures gradle build cache is warm for failure experiments."
  nexmark_failure_ensure_compiled

  for query in 3 8; do
    par="${EXPERIMENT_TO_PARALLELISM["NEXMARK_Q$query"]}"
    path="$path_prefix/nexmark_failure/$system/q$query"
    throughput="${QUERY_TO_THROUGHPUT[$query]}"
    kill_depth="${QUERY_TO_KILL_DEPTH[$query]}"

    reset_flink_cluster $system
    clear_kafka_topics $par

    if [ "$system" = "clonos" ]; then
      echoinfo "Starting configuration: SYS:$system;Q:$query;PAR:$par;CI:$D_CI;THROUGHPUT:$throughput;DSD:$D_DSD_CLONOS_FAILURE;PTI:$D_PTI_CLONOS;KD:$kill_depth"
      jobstr="$system;$query;$par;$D_CI;$throughput;$D_DSD_CLONOS_FAILURE;$D_PTI_CLONOS;$kill_depth"
    elif [ "$system" = "flink" ]; then
      echoinfo "Starting configuration: SYS:$system;Q:$query;PAR:$par;CI:$D_CI;THROUGHPUT:$throughput;DSD:$D_DSD_FLINK;PTI:$D_PTI_FLINK;KD:$kill_depth"
      jobstr="$system;$query;$par;$D_CI;$throughput;$D_DSD_FLINK;$D_PTI_FLINK;$kill_depth"
    fi
    start_nexmark_failure_experiment $jobstr $path
  done

  echo -e "---------------------------- Starting Synthetic Failure Experiments -------------------------------"

  #For synthetic failure experiments, we simply do two configurations (multiple and concurrent failures) using the default parameters.
  #See file below to find definitions of each parameter
  . ./2.2_synthetic_failure_experiments.sh
  for failure_type in "multiple" "concurrent"; do
    par="${EXPERIMENT_TO_PARALLELISM["SYNTH_${failure_type^^}"]}"
    path="$path_prefix/synthetic_failure/$system/fail_$failure_type"
    mkdir -p "$path"
    jobstr="$system;$D_THR;$D_LTI;$D_WI;$D_DSD;$D_PTI;$failure_type;$D_KD;$D_CI;$D_SS;$D_AS;$D_KEYS;$par;$D_D;$D_SHFL;$D_O;$D_W_SIZE;$D_W_SLIDE;$D_ST;$D_TC;$D_GEN_TS;$D_GEN_RAND;$D_GEN_SER"

    reset_flink_cluster $system
    clear_kafka_topics $par

    echoinfo "Starting configuration: FAIL_TYPE: $failure_type"
    start_synthetic_failure_experiment $path $jobstr
  done

done
