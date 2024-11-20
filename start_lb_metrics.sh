#!/usr/bin/env bash

LOG_DIR=$SCRATCH/cms/sonic/cmssw_14_1_0_pre7/Logs
HAPROXY_CFG=$SCRATCH/cms/sonic/cmssw_14_1_0_pre7/haproxy.cfg
CFS_HAPROXY_CFG=$CFS/dasrepo/$USER/haproxy.cfg
CFS_PROMETHEUS_JSON=$CFS/dasrepo/$USER/targets.json


# Check if the script received exactly one argument
if [ $# -ne 1 ]; then
  echo "Usage: $0 <job_id>"
  exit 1
fi

# Store the argument in a variable
SLURM_JOB_ID=$1

# Function: _generate_ips
_generate_ips() {
    #get nodes
    nodes=$(scontrol show hostnames $(scontrol show job $SLURM_JOB_ID --json | jq -r '.jobs[0].nodes'))
    nodes_array=( $nodes )
    num_nodes=${#nodes_array[@]}
    ips_address_array=()

    for node_address in "${nodes_array[@]}"; do
        ips_address_array+=($(getent hosts "$node_address" | awk '{ print $1 }'))
    done
}

# Function: load_balancer
load_balancer() {
    echo "> Generating LB cfg"
    chmod a+r $CFS_HAPROXY_CFG
    cat $HAPROXY_CFG > $CFS_HAPROXY_CFG
    echo "" >> $CFS_HAPROXY_CFG

    
    for ((n=0; n<num_nodes; n++)); do
        for i in 0 1 2 3; do
            echo -e "  server ${nodes_array[$n]}_${i} ${ips_address_array[$n]}:$((8001 + $i*10)) check proto h2" >> $CFS_HAPROXY_CFG
        done
    done
}

# Function: prometheus
prometheus() {
    echo "> Generate Prometheus cfg"
    chmod a+r $CFS_PROMETHEUS_JSON

    # Initialize an empty array to hold the JSON objects
    json_array="[]"

    for ((n=0; n<num_nodes; n++)); do
        for i in 0 1 2 3; do
            json_object=$(jq -n \
                --arg address "${ips_address_array[$n]}:$((8002 + $i*10))" \
                --arg server "${nodes_array[$n]}_${i}" \
                '{targets: [$address], labels: {server: $server}}')
            json_array=$(echo "$json_array" | jq --argjson obj "$json_object" '. + [$obj]')
        done
    done
    echo "$json_array" > "$CFS_PROMETHEUS_JSON"
}


# Main function
main() {
    _generate_ips
    load_balancer
    prometheus
}

# Call the main function
main
