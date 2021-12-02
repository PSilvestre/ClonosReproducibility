INPUT_TOPIC="benchmark-input"
OUTPUT_TOPIC="benchmark-output"

NUM_PRODUCERS_PER_HOST=2 #use 2 cores to generate data in data generators

if [ "$REMOTE" = "0" ]; then
  FLINK_ADDR=localhost:8081
  KAFKA_BOOTSTRAP_ADDR=172.17.0.1:9092 #TODO check this...
  KAFKA_EXTERNAL_ADDR=172.17.0.1:9092
  ZK_ADDR=localhost:2181
else
  FLINK_ADDR=0.0.0.0:31234
  KAFKA_BOOTSTRAP_ADDR=$(kubectl get svc | grep ClusterIP | grep kafka | grep -v headless | awk {'print $3'}):9092
  NODE_EXTERNAL_IP=$(ip addr show eth0 | grep "inet\b" | awk '{print $2}' | cut -d/ -f1)
  KAFKA_PORT=31090
  KAFKA_EXTERNAL_ADDR=$NODE_EXTERNAL_IP:$KAFKA_PORT
  ZK_ADDR=$(kubectl get svc | grep ClusterIP | grep zookeeper | grep -v headless | awk {'print $3'}):2181
fi

function clear_kafka_topics() {
  local p=$1

  echoinfo "Resetting Kafka Topics for new experiment" >&2
  ./kafka/bin/kafka-configs.sh --zookeeper "$ZK_ADDR" --alter --entity-type topics --add-config retention.ms=1000 --entity-name $INPUT_TOPIC > /dev/null 2>&1
  ./kafka/bin/kafka-configs.sh --zookeeper "$ZK_ADDR" --alter --entity-type topics --add-config retention.ms=1000 --entity-name $OUTPUT_TOPIC  > /dev/null 2>&1
  sleep 1

  ./kafka/bin/kafka-configs.sh --zookeeper "$ZK_ADDR" --alter --entity-type topics --delete-config retention.ms --entity-name $INPUT_TOPIC > /dev/null 2>&1
  ./kafka/bin/kafka-configs.sh --zookeeper "$ZK_ADDR" --alter --entity-type topics --delete-config retention.ms --entity-name $OUTPUT_TOPIC > /dev/null 2>&1
  sleep 1

  ./kafka/bin/kafka-topics.sh --zookeeper "$ZK_ADDR" --topic $INPUT_TOPIC --delete > /dev/null 2>&1
  ./kafka/bin/kafka-topics.sh --zookeeper "$ZK_ADDR" --topic $OUTPUT_TOPIC --delete > /dev/null 2>&1
  sleep 1

  ./kafka/bin/kafka-topics.sh --create --zookeeper "$ZK_ADDR" --topic $INPUT_TOPIC --partitions "$p" --replication-factor 1 > /dev/null 2>&1
  ./kafka/bin/kafka-topics.sh --create --zookeeper "$ZK_ADDR" --topic $OUTPUT_TOPIC --partitions "$p" --replication-factor 1 > /dev/null 2>&1
  sleep 1
}

function get_job_vertexes() {
  local jobid=$1

  local response=$(curl -sS -X GET "http://$FLINK_ADDR/jobs/$jobid")
  local vertex_ids=($(echo $response | jq '.vertices[] | .id' | tr -d '"'))
  echo "${vertex_ids[@]}"
}

function get_vertex_host() {
  local jobid=$1
  local vertex=$2
  local p=$3
  local tm=$(curl -sS -X GET "http://$FLINK_ADDR/jobs/$jobid/vertices/$vertex/subtasks/$p" | jq '.host' | tr -d '"')
  echo "$tm"
}

function reset_flink_cluster() {
  echoinfo "Resetting Flink cluster for new experiment"
  if [ "$REMOTE" = "0" ]; then
    $(cd ./compose && docker-compose down -v 2> /dev/null && docker-compose up -d --scale taskmanager=$NUM_TASKMANAGERS_REQUIRED 2> /dev/null)
  else
    kubectl delete pod $(kubectl get pods | grep flink | awk {'print $1'})
  fi
}

function kill_taskmanager() {
  local taskmanager_to_kill=$1
  if [ "$REMOTE" = "0" ]; then
    docker kill "$taskmanager_to_kill"
  else
    kubectl delete --grace-period=0 --force pod "$taskmanager_to_kill"
  fi
  echo "Kiled taskmanager $taskmanager_to_kill" >&2
}

function perform_failures() {
  local jobid=$1
  local path=$2
  local d=$3
  local p=$4
  local kd=$5
  local killtype=$6

  # Get taskmanagers used by job
  local vertex_ids=($(get_job_vertexes $jobid))

  local taskmanagers_used=($(for vid in ${vertex_ids[@]}; do curl -sS -X GET "http://$FLINK_ADDR/jobs/$jobid/vertices/$vid/taskmanagers" | jq '.taskmanagers[] | .host' | tr -d '"' | tr ":" " " | awk {'print $1'}; done))

  local kill_time=$(date +%s%3N)

  if [ "$killtype" = "single" ]; then
    #Kill par 0 at the requested depth
    local depth_to_kill=$((kd - 1))
    local par_to_kill=0
    local index_to_kill=$((depth_to_kill * p + par_to_kill))
    local taskmanager_to_kill=${taskmanagers_used[$index_to_kill]}
    kill_taskmanager "$taskmanager_to_kill"
    echo "$taskmanager_to_kill $depth_to_kill $par_to_kill $kill_time" >>"$path"/killtime
  elif [ "$killtype" = "concurrent" ]; then
    #Iterate Depths, killing one at each depth at  roughly same time
    for kdi in $(#TODO, might have to change this to d_start d_end
      seq 1 "$d"
    ); do
      par_to_kill=0
      index_to_kill=$((kdi * p + par_to_kill))
      local taskmanager_to_kill=${taskmanagers_used[$index_to_kill]}
      kill_taskmanager "$taskmanager_to_kill"
      echo "$taskmanager_to_kill $kdi $par_to_kill $kill_time" >>"$path"/killtime
    done
  elif [ "$killtype" = "multiple" ]; then
    #Iterate Depths, killing one random task at each depth and sleeping between
    for kdi in $(#TODO, might have to change this to d_start d_end
      seq 1 "$d"
    ); do
      par_to_kill=$((RANDOM % $p))
      index_to_kill=$((kdi * p + par_to_kill))
      local taskmanager_to_kill=${taskmanagers_used[$index_to_kill]}
      kill_taskmanager "$taskmanager_to_kill"
      echo "$taskmanager_to_kill $kdi $par_to_kill $kill_time" >>"$path"/killtime
      sleep $SLEEP_BETWEEN_RANDOM_KILLS
    done
  fi
}

function push_job_jar() {
  local jar_name=$1
  local response=$(curl -sS -X POST -H "Expect:" -F "jarfile=@job-$jar_name.jar" http://$FLINK_ADDR/jars/upload)
  echo "PUSH: $response" >&2
  local id=$(echo "$response" | jq '.filename' | tr -d '"' | tr "/" "\n" | tail -n1)
  sleep 10
  echo "$id"
}

function cancel_job() {
  local jobid=$(get_job_id)
  curl -sS -X PATCH "http://$FLINK_ADDR/jobs/$jobid?mode=cancel" >/dev/null
  sleep 3
}

function get_job_id() {
  local jobid=$(curl -sS -X GET "http://$FLINK_ADDR/jobs" | jq '.jobs[0].id' | tr -d '"')
  echo $jobid
}

function start_data_generators() {
  duration_seconds=$1
  throughput=$2

  IFS=";" read -r -a ips <<<"${DATA_GENERATOR_IPS}"

  size=${#ips[@]}
  num_prod_tot=$(($NUM_PRODUCERS_PER_HOST * $size + $NUM_PRODUCERS_PER_HOST)) #+NUM_PRODUCERS_PER_HOST for the local machine

  throughput_per_prod=$(( throughput / num_prod_tot ))
  num_records_per_prod=$(( throughput_per_prod * duration_seconds ))
  echo "Num Producers: $num_prod_tot"
  echo "Requested throughput: $throughput"
  echo "Throughput per prod: $throughput_per_prod"
  echo "Num records per prod: $num_records_per_prod"

  #Start local producers
  prodindex=0
  for i in $(seq $NUM_PRODUCERS_PER_HOST); do
    timeout $duration_seconds /home/ubuntu/kafka/bin/kafka-producer-perf-test.sh --dist-producer-index $prodindex --dist-producer-total $num_prod_tot --topic $INPUT_TOPIC --num-records $num_records_per_prod --throughput $throughput_per_prod --producer-props bootstrap.servers=$KAFKA_EXTERNAL_ADDR key.serializer=org.apache.kafka.common.serialization.StringSerializer value.serializer=org.apache.kafka.common.serialization.StringSerializer > /dev/null &
    prodindex=$((prodindex + 1))
  done

  #If there are external producers, we start them now.
  for ip in ${ips[@]}; do
    for i in $(seq $NUM_PRODUCERS_PER_HOST); do
      ssh -o StrictHostKeyChecking=no $ip "timeout $duration_seconds ~/kafka/bin/kafka-producer-perf-test.sh --dist-producer-index $prodindex --dist-producer-total $num_prod_tot --topic $INPUT_TOPIC --num-records $num_records_per_prod --throughput $throughput_per_prod --producer-props bootstrap.servers=$KAFKA_EXTERNAL_ADDR key.serializer=org.apache.kafka.common.serialization.StringSerializer value.serializer=org.apache.kafka.common.serialization.StringSerializer > /dev/null" &
      prodindex=$((prodindex + 1))
    done
  done

}
