#!/bin/bash

#Limit Gradle Mem usage
export GRADLE_OPTS="-Xmx128m -Dorg.gradle.jvmargs='-Xmx512m -XX:MaxPermSize=128m'"

# QUERY|PAR|KD|THROUGHPUT|

#TODO
# --numEvents may also be a factor for overhead queries
#   I think we will need to adjust the number of events per query.

D_PARALLELISM_OVERHEAD=25
D_PARALLELISM_FAILURE=5

D_CI=5000

D_DSD_FLINK=0 #Flink does not have this parameter
D_DSD_CLONOS_FAILURE=1

D_PTI_CLONOS=10
D_PTI_FLINK=0 #Flink does not have this parameter

FAILURE_TOTAL_EXPERIMENT_TIME=230
INIT_TIME=90
TIME_TO_KILL=60
MEASUREMENT_DURATION=$((FAILURE_TOTAL_EXPERIMENT_TIME - INIT_TIME))

function build_args() {
  jobstr=$1
  type=$2

  IFS=";" read -r -a params <<<"${jobstr}"

  #General Job Parameters.
  local system="${params[0]}"
  local q="${params[1]}"
  local p="${params[2]}"
  local ci="${params[3]}"
  local ne="${params[4]}" #Number of events total to produce. In failure mode, this is used to calculate the producer throughput.

  # Parameters only used if system="clonos"
  local dsd="${params[5]}"
  local pti="${params[6]}"

  local args="--flinkMaster=$FLINK_ADDR "
  args+="--runner=${system^}Runner "
  args+="--query=$q "
  args+="--parallelism=$p "
  args+="--checkpointingInterval=$ci"
  args+="--suite=STRESS "
  args+="--streamTimeout=60 "
  args+="--streaming=true"
  args+="--manageResources=false"
  args+="--monitorJobs=true"
  args+="--externalizedCheckpointsEnabled=true"
  args+="--objectReuse=true"
  args+="--debug=true "
  args+="--shutdownSourcesOnFinalWatermark=true"
  #--shutdownSourcesAfterIdleMs=100
  args+="--autoWatermarkInterval=200"
  args+="--useWallclockEventTime=false"
  args+="--probDelayedEvent=0"
  args+="--slotSharingEnabled=false"
  args+="--numEvents=$ne"

  if [ "$system" = "clonos" ]; then
    args+="--determinantSharingDepth=$dsd"
    args+="--periodicTimeInterval=$pti"
  fi

  if [ $type != "overhead" ]; then
    #If not overhead (producer or failure) we have to append kafka info
    args+="--bootstrapServers=$KAFKA_BOOTSTRAP_ADDRESS"
    args+="--sourceType=KAFKA"
    args+="--kafkaTopic=$INPUT_TOPIC"
    args+="--sinkType=KAFKA"
    args+="--kafkaResultsTopic=$OUTPUT_TOPIC"
  fi

  if [ $type = "producer" ]; then
    local produce_throughput=$((ne / FAILURE_TOTAL_EXPERIMENT_TIME))
    args+="--pubSubMode=PUBLISH_ONLY"
    args+="--isRateLimited=true"
    args+="--firstEventRate=$produce_throughput"
    args+="--nextEventRate=$produce_throughput"
  fi

  echo "$args"
}

function start_nexmark_failure_experiment() {
  jobstr=$1
  path=$2

  mkdir -p "$path"

  IFS=";" read -r -a params <<<"${jobstr}"
  local system="${params[0]}"
  local p="${params[2]}"
  local kd="${params[7]}"

  args=$(build_args $jobstr "failure")

  args_producer=$(build_args $jobstr "producer")

  echo "Running publisher"
  timeout $FAILURE_TOTAL_EXPERIMENT_TIME bash -c "cd ./beam && ./gradlew :sdks:java:testing:nexmark:run -Pnexmark.runner=\":runners:$system:1.7\" -Pnexmark.args=$args_producer" &
  echo "Running Job"
  timeout $FAILURE_TOTAL_EXPERIMENT_TIME bash -c "cd ./beam && ./gradlew :sdks:java:testing:nexmark:run -Pnexmark.runner=\":runners:$system:1.7\" -Pnexmark.args=$args" &
  sleep $INIT_TIME

  # Begin measuring throughput and latency, sleep until ready to fail
  local resolution=2
  python3 ./end_to_end_latency_measurer.py -k $KAFKA_EXTERNAL_ADDR -o $OUTPUT_TOPIC -r $resolution -p $p -d $MEASUREMENT_DURATION -mps 1 -t false >$path/latency &
  python3 ./throughput_measurer.py $MEASUREMENT_DURATION 1 $KAFKA_EXTERNAL_ADDR $OUTPUT_TOPIC verbose >$path/throughput &
  sleep $TIME_TO_KILL

  local jobid=$(get_job_id)
  perform_failures "$jobid" "$path" 0 $p $kd "single"

  sleep $((MEASUREMENT_DURATION - TIME_TO_KILL))

  echo "Canceling the job with id $jobid"
  cancel_job
}

function start_nexmark_overhead_experiment() {
  jobstr=$1
  path=$2

  IFS=";" read -r -a params <<<"${jobstr}"
  local system="${params[0]}"
  local q="${params[1]}"
  local p="${params[2]}"
  local ci="${params[3]}"
  local ne="${params[4]}" #Number of events total to produce. In failure mode, this is used to calculate the producer throughput.
  # Parameters only used if system="clonos"
  local dsd="${params[5]}"
  local pti="${params[6]}"

  args=$(build_args $jobstr "overhead")

  measured_throughput=$(cd ./beam && ./gradlew :sdks:java:testing:nexmark:run -Pnexmark.runner=":runners:$system:1.7" -Pnexmark.args=\"$args\" | grep 0000 | grep -v "query" | awk '{print $3}')
  echo -e "$system\t$q\t$p\t$dsd\t$ne\t$measured_throughput" >> $path

}
