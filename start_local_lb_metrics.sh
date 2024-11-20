#!/usr/bin/env bash

LOG_DIR=$SCRATCH/cms/sonic/cmssw_14_1_0_pre7/Logs

HAPROXY_IMAGE=haproxy:2.9-alpine
HAPROXY_CFG=/pscratch/sd/a/asnaylor/cms/sonic/cmssw_14_1_0_pre7/haproxy.cfg

PROMETHEUS_IMAGE=prom/prometheus:v2.54.1
PROMETHEUS_CFG=/pscratch/sd/a/asnaylor/cms/sonic/cmssw_14_1_0_pre7/prometheus.yml
PROMETHEUS_DATA=/pscratch/sd/a/asnaylor/cms/sonic/cmssw_14_1_0_pre7/prometheus

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
    echo "> Starting LB"
    LB_TMP_FILE=$(mktemp)
    chmod a+r $LB_TMP_FILE
    cat $HAPROXY_CFG > $LB_TMP_FILE
    echo "" >> $LB_TMP_FILE

    
    for ((n=0; n<num_nodes; n++)); do
        for i in 0 1 2 3; do
            echo -e "  server ${nodes_array[$n]}_${i} ${ips_address_array[$n]}:$((8001 + $i*10)) check proto h2" >> $LB_TMP_FILE
        done
    done

    # echo "LB tmpfile: $LB_TMP_FILE"
    # podman-hpc run --rm --net host \
    #            --mount type=bind,source=$LB_TMP_FILE,destination=/usr/local/etc/haproxy/haproxy.cfg,readonly \
    #          $HAPROXY_IMAGE

    #start image
    shifter --module=none \
            --image=$HAPROXY_IMAGE \
            haproxy -f $LB_TMP_FILE &
    
    # save pid
    LB_pid=$!
    echo $LB_pid > lb.pid
}

# Function: prometheus
prometheus() {
    echo "> Starting Prometheus"
    PROM_TMP_FILE=$(mktemp)
    chmod a+r $PROM_TMP_FILE
    cat $PROMETHEUS_CFG > $PROM_TMP_FILE
    echo "" >> $PROM_TMP_FILE

    PROM_CFG_STRING=$(cat <<'EOF'
      - targets: ['IP']
        labels:
          server: 'NODE'
EOF
)
    for ((n=0; n<num_nodes; n++)); do
        for i in 0 1 2 3; do
            echo "$PROM_CFG_STRING" | sed -e "s/NODE/${nodes_array[$n]}_${i}/g" -e "s/IP/${ips_address_array[$n]}:$((8002 + $i*10))/g" >> $PROM_TMP_FILE
        done
    done

    # echo "Prometheus tmpfile: $PROM_TMP_FILE"
    #start image
    shifter --module=none \
            --image=$PROMETHEUS_IMAGE \
            /bin/prometheus --config.file=$PROM_TMP_FILE --storage.tsdb.path=$PROMETHEUS_DATA --storage.tsdb.retention.time=30d &

    # save pid
    PROM_pid=$!
    echo $PROM_pid > prom.pid
}

# Function: grafana
grafana() {
    echo "> Staring Grafana"
}

# Main function
main() {
    _generate_ips
    load_balancer
    #prometheus
    #grafana
    #wait
    echo 'Kill with - kill `cat lb.pid prom.pid`'
}

# Call the main function
main
