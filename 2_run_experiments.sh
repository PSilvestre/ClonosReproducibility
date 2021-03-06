#!/bin/bash

#Load functionality shared by all experiments
. experiments_shared_code.sh

. experimental_parameters.sh

path_prefix=$1

overhead_path="$path_prefix/nexmark_overhead"
echo -e "SYSTEM\tQUERY\tPARALLELISM\tDSD\tNUM_EVENTS\tTHROUGHPUT" >>$overhead_path

max_par=$(echo "${EXPERIMENT_TO_PARALLELISM[@]}" | tr " " "\n" | sort | tail -n1)
NUM_TASKMANAGERS_REQUIRED=$((max_par * 6 * 2)) # MAX_PAR * MAX_DEPTH * 2 (standby tasks)


for system in "clonos" "flink" ; do
  set_failover_strategy $system
  # Source nexmark testing scripts
  . ./2.1_nexmark_experiments.sh

  if [ "$RUN_OVERHEAD" = "1" ] ; then
    echo -e "----------------------------- Starting Nexmark Overhead Experiments -------------------------------"
    change_beam_branch "clonos-runner"
    set_number_of_standbys 0
    set_sensitive_failure_detection "false"
    set_heartbeat 20000000 200000000 #Reduces flakyness of tests because no failures should happen (No false positive failure detections).

    redeploy_flink_cluster $system
    for query in 1 2 3 4 5 6 7 8 9 11 12 13 14; do
      num_events=${QUERY_TO_NUM_EVENTS[$query]}
      par=${EXPERIMENT_TO_PARALLELISM["OVERHEAD"]}
      if [ "$system" = "clonos" ]; then
        #If the system is Clonos, run two configurations full DSD and one DSD
        for dsd in "-1" "1"; do
          for attempt in {1..3}; do
            reset_flink_cluster $system
            echoinfo "Starting configuration: SYS:$system;Q:$query;PAR:$par;CI:$D_CI;NE:$num_events;DSD:$dsd;PTI:$D_PTI_CLONOS"
            echoinfo "Attempt $attempt"
            jobstr="$system;$query;$par;$D_CI;$num_events;$dsd;$D_PTI_CLONOS"
            res=$(start_nexmark_overhead_experiment $jobstr $overhead_path)
            [ "$res" != "0" ] || break
          done
        done
      elif [ "$system" = "flink" ]; then
        for attempt in {1..3}; do
          reset_flink_cluster $system
          echoinfo "Starting configuration: SYS:$system;Q:$query;PAR:$par;CI:$D_CI;NE:$num_events;DSD:$D_DSD_FLINK;PTI:$D_PTI_FLINK"
          echoinfo "Attempt $attempt"
          jobstr="$system;$query;$par;$D_CI;$num_events;$D_DSD_FLINK;$D_PTI_FLINK"
          res=$(start_nexmark_overhead_experiment $jobstr $overhead_path)
          [ "$res" != "0" ] || break
        done
      fi
    done
  else
    echoinfo "--------------------------------------- Skipping overhead experiments... --------------------------------"
    echoinfo "Copying overhead measurements provided in paper..."
    cp ./data/presented_in_paper/nexmark_overhead $overhead_path
  fi

  echo -e "----------------------------- Starting Nexmark Failure Experiments --------------------------------"
  change_beam_branch "clonos-runner-failure-experiments"
  set_number_of_standbys 1
  set_heartbeat 4000 6000
  set_sensitive_failure_detection "true"
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
  set_number_of_standbys 1
  set_heartbeat 4000 6000
  set_sensitive_failure_detection "true"
  redeploy_flink_cluster $system
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
