#!/bin/bash

#===================PARAMETERS DEFINABLE FOR EXPERIMENT=========================
# As you can see, we have a large number of configuration options, which were not discussed in paper experiments.
# By default, we leave here the values used in the paper experiments.
# We leave these here for two reasons:
#		1. The synthetic job still requires them to be configured at launch time.
#		2. The reproducibility reviewers may want to test new configurations

#GENERAL
D_SYS="clonos"                                                          #System to test
D_THR="250000"                                                          #Target throughput (negative number for unlimited)
D_LTI="0"                                                               #Latency Tracking interval (0 is disabled)
D_WI="0"                                                                #Watermark interval (0 is disabled)

#CLONOS SPECIFIC OPTIONS
D_DSD="-1"                                                              #Determinant Sharing Depth (-1 for full sharing)
D_PTI="5"                                                               #Periodic Time Interval (Sets the "wall-clock time granularity" for the system)

#FAILURE OPTIONS
D_KT="single"                                                           #Kill Type (single failure synthetic experiments were not presented)
D_KD=2                                                                  #Kill Depth (1 based, meaning 1 is sources)

#DATAFLOW JOB OPTIONS
D_CI=5000                                                               #Checkpoint interval
D_SS=100000000                                                          #State size per operator. Total SS will be D*P*SS (100Mib=100000000)
D_AS=0.0001                                                             #Access State - Percentage of Records which access and mutate state
D_KEYS="10000"                                                          #Number of keys each partition will process (each key will hold SS/KEYS state size)
D_P=5                                                                   #Parallelism of each layer
D_D=5                                                                   #Depth - Number of layers or tasks, not counting sources and sinks
D_SHFL="true"                                                           #Shuffle connections or fully data-parallel
D_O="map"                                                               #Operator type: "map" or "window".
D_W_SIZE=1000                                                           #Window Size (Only if operator is window)
D_W_SLIDE=100                                                           #Window Slide (Only if operator is window)
D_ST=0                                                                  #Sleep Time (Iterations in a non-yielding loop)
D_TC="processing"                                                       #Time Characteristic: "processing", "event" or "periodic"
D_GEN_TS="false"                                                        #Generate Timestamps on every record?
D_GEN_RAND="false"                                                      #Generate Random number on every record?
D_GEN_SER="false"                                                       #Generate Serializable test object (a Long) on every record?


#DISABLED OPTIONS
    #NOTE: Graph-only (D_GO) and Transactional (D_T) should be left as is,
    # as this version of the script has been stripped of the extra functionality needed for them.
D_T="false"                                                             #Uses transactional exactly-once delivery semantics
D_GO="false"                                                            #Does not use kafka, instead source operators generate data

#Experiment time settings
JOB_WARM_UP_TIME=30                                                     #How long to let the system warm-up
MEASUREMENT_DURATION=120                                                #Total time to measure the systems throughput or latency
FAILURE_FREE_RUN_TIME=30                                                #How long into MEASUREMENT_DURATION is the kill performed
TOTAL_EXPERIMENT_TIME=$((JOB_WARM_UP_TIME + MEASUREMENT_DURATION))      #Total time the system will run (the time data producers have to be active)
SLEEP_AFTER_KILL=$((MEASUREMENT_DURATION - FAILURE_FREE_RUN_TIME + 10)) #How long after killing we should keep measuring
SLEEP_BETWEEN_RANDOM_KILLS=5

run_synthetic_job() {
  local jarid=$1
  local jobstr=$2

  IFS=";" read -r -a params <<<"${jobstr}"

  local sys="${params[0]}"
  local throughput="${params[1]}"
  local lti="${params[2]}"
  local wi="${params[3]}"
  local dsd="${params[4]}"
  local pti="${params[5]}"
  #local kt="${params[6]}"
  #local kd="${params[7]}"
  local ci="${params[8]}"
  local ss="${params[9]}"
  local as="${params[10]}"
  local keys="${params[11]}"
  local p="${params[12]}"
  local d="${params[13]}"
  local shuffle="${params[14]}"
  local operator="${params[15]}"
  local wsize="${params[16]}"
  local wslide="${params[17]}"
  local st="${params[18]}"
  local tc="${params[19]}"
  local gen_ts="${params[20]}"
  local gen_random="${params[21]}"
  local gen_serializable="${params[22]}"

  #Build up JSON of job description. Our Flink/Clonos Job JAR then configures itself from these params
  data_str="{\"programArgs\":\" --experiment-checkpoint-interval-ms $ci --experiment-state-size $ss "
  data_str+="--experiment-parallelism $p --experiment-depth $d --sleep $st --experiment-window-size $wsize "
  data_str+="--experiment-window-slide $wslide --experiment-access-state $as --experiment-operator $operator "
  data_str+="--experiment-transactional $D_T --experiment-time-char $timechar "
  data_str+="--experiment-latency-tracking-interval $lti --experiment-watermark-interval $wi "
  data_str+="--experiment-determinant-sharing-depth $dsd --experiment-shuffle $shuffle "
  data_str+="--experiment-overhead-measurement $D_GO --target-throughput $throughput "
  data_str+="--experiment-time-setter-interval $pti --num-keys-per-partition $keys "
  data_str+="--bootstrap.servers $KAFKA_BOOTSTRAP_ADDR  --experiment-gen-ts $gen_ts --experiment-gen-random $gen_random"
  data_str+=" --experiment-gen-serializable $gen_serializable \"}"

  local response=$(curl -sS -X POST --header "Content-Type: application/json;charset=UTF-8" --data "$data_str" "http://$FLINK_ADDR/jars/$jarid/run?allowNonRestoredState=false")
  echo "RUN: $response" >&2

  local job_id=$(echo "$response" | jq ".jobid" | tr -d '"')
  sleep 5
  echo $job_id
}

start_synthetic_failure_experiment() {
  local path=$1
  mkdir -p "$path"
  shift 1
  local jobstr=$1
  shift 1

  IFS=";" read -r -a params <<<"${jobstr}"

  local system="${params[0]}"
  local throughput="${params[1]}"
  local p="${params[12]}"

  topic_partitions="$p" #Number of topic partitions should = source/sink operator parallelism for best performance.
  clear_kafka_topics $topic_partitions
  reset_flink_cluster $num_nodes_needed

  id=$(push_job_jar $system)

  start_distributed_producers $TOTAL_EXPERIMENT_TIME $throughput
  echo "$throughput" > $path/input-throughput

  sleep 3 #Allow producers to begin producing data

  local jobid=$(run_synthetic_job "$id" "$jobstr")

  sleep $JOB_WARM_UP_TIME

  #System is warmed-up. Begin measuring end-to-end throughput and latency.
  #Then, sleep until it is time to perform failures

  local resolution=$((throughput / 5 + 1))
  local resolution=$(echo "${resolution%.*}")
  LATENCY_MEASUREMENTS_PER_SECOND=3
  python3 end_to_end_latency_measurer.py -k $KAFKA_EXTERNAL_ADDR -o $OUTPUT_TOPIC -r $resolution -p $p -d $MEASUREMENT_DURATION -mps $LATENCY_MEASUREMENTS_PER_SECOND -t $D_T >$path/latency &

  python3 ./throughput_measurer.py $MEASUREMENT_DURATION 3 $KAFKA_EXTERNAL_ADDR $OUTPUT_TOPIC verbose >$path/throughput &

  sleep $FAILURE_FREE_RUN_TIME

  perform_failures "$jobid" "$path" $d $p $kd $killtype

  sleep $SLEEP_AFTER_KILL

  echo "Canceling the job with id $jobid" >&2
  cancel_job
}
