
# ===================================================================================================================
# Together with the constants defined in 2.1_nexmark_experiments.sh and 2.2_synthetic_experiments.sh,
# these are the original settings used in paper experiments.

# We use different numbers of events for different queries to ensure similar runtimes for Overhead experiments
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

# Parallelism used in experiments. To see the full benefit of Clonos must be >= 2
declare -A EXPERIMENT_TO_PARALLELISM
EXPERIMENT_TO_PARALLELISM["OVERHEAD"]=25
EXPERIMENT_TO_PARALLELISM["SYNTH_MULTIPLE"]=5
EXPERIMENT_TO_PARALLELISM["SYNTH_CONCURRENT"]=5
EXPERIMENT_TO_PARALLELISM["NEXMARK_Q3"]=5
EXPERIMENT_TO_PARALLELISM["NEXMARK_Q8"]=5

# Kill Depth in failure experiments. We set these such that they kill stateful operators (such as join)
declare -A QUERY_TO_KILL_DEPTH
QUERY_TO_KILL_DEPTH[3]=3
QUERY_TO_KILL_DEPTH[8]=2



# If the user requested us to scale down the experiments...
if [ "$SCALE_DOWN" = "1" ] ; then
  # Reduce an order of magnitude in the number of events of nexmark overhead experiments
  QUERY_TO_NUM_EVENTS[1]=10000000
  QUERY_TO_NUM_EVENTS[2]=10000000
  QUERY_TO_NUM_EVENTS[3]=10000000
  QUERY_TO_NUM_EVENTS[4]=1000000
  QUERY_TO_NUM_EVENTS[5]=1000000
  QUERY_TO_NUM_EVENTS[6]=1000000
  QUERY_TO_NUM_EVENTS[7]=1000000
  QUERY_TO_NUM_EVENTS[8]=10000000
  QUERY_TO_NUM_EVENTS[9]=1000000
  QUERY_TO_NUM_EVENTS[11]=1000000
  QUERY_TO_NUM_EVENTS[12]=1000000
  QUERY_TO_NUM_EVENTS[13]=1000000
  QUERY_TO_NUM_EVENTS[14]=1000000


  #Reduce the generator throughput in Nexmark failure experiments
  QUERY_TO_THROUGHPUT[3]=10000
  QUERY_TO_THROUGHPUT[8]=10000

  #Reduce the parallelism considerably
  EXPERIMENT_TO_PARALLELISM["OVERHEAD"]=5
  EXPERIMENT_TO_PARALLELISM["SYNTH_MULTIPLE"]=3
  EXPERIMENT_TO_PARALLELISM["SYNTH_CONCURRENT"]=3
  EXPERIMENT_TO_PARALLELISM["NEXMARK_Q3"]=3
  EXPERIMENT_TO_PARALLELISM["NEXMARK_Q8"]=3
fi
