#!/bin/bash

#Limit Gradle Mem usage
export GRADLE_OPTS="-Xmx256m -Dorg.gradle.jvmargs='-Xmx1024m -XX:MaxPermSize=256m'"

# Checkpoint every 10 seconds
D_CI=10000

D_DSD_CLONOS_FAILURE=1
D_DSD_FLINK=0 #Flink does not have this parameter

D_PTI_CLONOS=10
D_PTI_FLINK=0 #Flink does not have this parameter

PRODUCER_ONLY_TIME=30
INIT_TIME=300 # 5 minutes of init time because the download of BEAM jars can take very long time.
TIME_TO_KILL=60
MEASUREMENT_DURATION=250
FAILURE_TOTAL_EXPERIMENT_TIME=$(( INIT_TIME + MEASUREMENT_DURATION ))
SLEEP_AFTER_KILL=$((MEASUREMENT_DURATION - TIME_TO_KILL + 30))

function build_args() {
  jobstr=$1
  type=$2

  IFS=";" read -r -a params <<<"${jobstr}"

  #General Job Parameters.
  local system="${params[0]}"
  local q="${params[1]}"
  local p="${params[2]}"
  local ci="${params[3]}"
  local ne="${params[4]}" #Number of events total to produce. In failure mode, this is producer throughput.

  # Parameters only used if system="clonos"
  local dsd="${params[5]}"
  local pti="${params[6]}"

  local args="--flinkMaster=$FLINK_ADDR "
  args+="--runner=${system^}Runner "
  args+="--query=$q "
  args+="--parallelism=$p "
  args+="--checkpointingInterval=$ci "
  args+="--suite=STRESS "
  args+="--streamTimeout=60 "
  args+="--streaming=true "
  args+="--manageResources=false "
  args+="--monitorJobs=true "
  args+="--externalizedCheckpointsEnabled=true "
  args+="--objectReuse=true "
  args+="--autoWatermarkInterval=200 "
  args+="--useWallclockEventTime=false "
  args+="--probDelayedEvent=0 "
  args+="--slotSharingEnabled=false "
  args+="--shutdownSourcesOnFinalWatermark=true "

  if [ "$system" = "clonos" ]; then
    args+="--determinantSharingDepth=$dsd "
    args+="--periodicTimeInterval=$pti "
  fi

  if [ $type = "overhead" ]; then
    args+="--numEvents=$ne "
    args+="--debug=true "
  else
    args+="--bootstrapServers=$KAFKA_BOOTSTRAP_ADDR "
    args+="--sourceType=KAFKA "
    args+="--kafkaTopic=$INPUT_TOPIC "
    args+="--sinkType=KAFKA "
    args+="--kafkaResultsTopic=$OUTPUT_TOPIC "

    args+="--debug=false "

    if [ $type = "producer" ]; then
      produce_throughput=$ne
      numEvents=$(( produce_throughput * ( FAILURE_TOTAL_EXPERIMENT_TIME + PRODUCER_ONLY_TIME ) ))

      args+="--pubSubMode=PUBLISH_ONLY "
      args+="--isRateLimited=true "
      args+="--numEvents=$numEvents "
      args+="--firstEventRate=$produce_throughput "
      args+="--nextEventRate=$produce_throughput "

    elif [ $type = "failure" ]; then
      args+="--pubSubMode=SUBSCRIBE_ONLY "
      args+="--isRateLimited=false "
    fi
  fi

  echo "$args"
}

function nexmark_failure_ensure_compiled() {
  jobstr="$system;1;1;5000;10000;1;10;-1"
  args=$(build_args $jobstr "producer" )
  pushd ./beam > /dev/null 2>&1
  timeout -s 9 300 bash -c "./gradlew :sdks:java:testing:nexmark:run -Pnexmark.runner=\":runners:$system:1.7\" -Pnexmark.args=\"$args\"" >/dev/null 2>&1
  popd >/dev/null 2>&1 #back to root
}

function start_nexmark_failure_experiment() {
  jobstr=$1
  path=$2

  mkdir -p "$path"

  IFS=";" read -r -a params <<<"${jobstr}"
  local system="${params[0]}"
  local p="${params[2]}"
  local kd="${params[7]}"


  echoinfo "Starting data producer job"
  args_producer=$(build_args $jobstr "producer")
  timeout -s 9 $(( FAILURE_TOTAL_EXPERIMENT_TIME + PRODUCER_ONLY_TIME )) bash -c "cd ./beam && ./gradlew :sdks:java:testing:nexmark:run -Pnexmark.runner=\":runners:$system:1.7\" -Pnexmark.args=\"$args_producer\"" >prod.txt 2>&1 &

  sleep $PRODUCER_ONLY_TIME

  echoinfo "Starting data consumer job"
  args=$(build_args $jobstr "failure" )
  timeout -s 9 $(( FAILURE_TOTAL_EXPERIMENT_TIME )) bash -c "cd ./beam && ./gradlew :sdks:java:testing:nexmark:run -Pnexmark.runner=\":runners:$system:1.7\" -Pnexmark.args=\"$args\"" > cons.txt 2>&1 &

  sleep $(( INIT_TIME ))

  echoinfo "Starting throughput and latency measurements."
  local resolution=2
  python3 ./end_to_end_latency_measurer.py -k $KAFKA_EXTERNAL_ADDR -o $OUTPUT_TOPIC -r $resolution -p $p -d $MEASUREMENT_DURATION -mps 1 -t false >$path/latency &
  python3 ./throughput_measurer.py $MEASUREMENT_DURATION 1 $KAFKA_EXTERNAL_ADDR $OUTPUT_TOPIC verbose >$path/throughput &
  sleep $TIME_TO_KILL

  local jobid=$(get_job_id 0)
  echoinfo "Performing failure on job: $jobid"
  perform_failures "$jobid" "$path" 0 $p $kd "single"

  sleep $SLEEP_AFTER_KILL
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

  results=$(bash -c "cd ./beam && ./gradlew :sdks:java:testing:nexmark:run -Pnexmark.runner=\":runners:$system:1.7\" -Pnexmark.args=\"$args\" 2>&1 ")
  measured_throughput=$(echo "$results" | grep 0000 | grep -v 'query' | grep -v 'event' | tail -n1 | awk '{print $3}')
  echoinfo "Q$q Throughput: $measured_throughput"
  echo -e "$system\t$q\t$p\t$dsd\t$ne\t$measured_throughput" >> $path

}
