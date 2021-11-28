declare -A SYSTEM_TO_FAILOVER_STRATEGY
SYSTEM_TO_FAILOVER_STRATEGY["flink"]="full"
SYSTEM_TO_FAILOVER_STRATEGY["clonos"]="standbytask"

function deploy_infra_kubernetes() {
  helm install hadoop ./kubernetes/charts/hadoop
  helm install confluent ./kubernetes/charts/cp-helm-charts
}

function deploy_sps_kubernetes() {
  local system=$1

  sed -i "s/^image:.*/image: $SYSTEM_CONTAINER_IMG/g" ./kubernetes/values.yaml
  sed -i "s/  fo_strategy:.*/  fo_strategy: ${SYSTEM_TO_FAILOVER_STRATEGY[$system]}/g" ./kubernetes/values.yaml

  helm install -f ./kubernetes/values.yaml sps ./kubernetes/charts/flink/
}

function tear_down_sps_kubernetes() {
  helm delete sps
}

function tear_down_infra_kubernetes() {
  helm delete hadoop
  helm delete confluent
}
