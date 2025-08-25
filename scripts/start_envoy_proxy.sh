#!/usr/bin/env bash

# Usage: ./envoy_proxy_lb.sh <shifter_image> <number_of_lb_nodes> <triton_servers>


LB_SHIFTER_IMAGE=${1}
N_LB_NODES=${2}
N_LB=$((4*N_LB_NODES))
TRITON_SERVERS="${@:3}"  # All arguments from position 3 onwards
TRITON_PORT=8001

# Convert Triton to array
TRITON_SERVERS_ARRAY=($TRITON_SERVERS)

# SLURM_LOCALID corresponds to HSN interface (0-3)
HSN_ID=${SLURM_LOCALID}
LB_ID=${SLURM_PROCID}
ENVOY_PORT=9000
ADMIN_PORT=9901
ENVOY_HOSTNAME=$(dig +short ${HOSTNAME}-hsn${HSN_ID})

echo "<> Starting Envoy LB on ${HOSTNAME} HSN interface ${HSN_ID}"
echo "<> Envoy port: ${ENVOY_PORT}, Admin port: ${ADMIN_PORT}"

# Create temp file
TMPFILE=$(mktemp /tmp/envoy-config.XXXXXX.yaml)
cat envoy-config.yaml > ${TMPFILE}

# Update the hostname + ports in the config
yq w -i ${TMPFILE} "admin.address.socket_address.address" "$ENVOY_HOSTNAME"
yq w -i ${TMPFILE} "admin.address.socket_address.port_value" "$ADMIN_PORT"

yq w -i ${TMPFILE} "static_resources.listeners[0].address.socket_address.address" "$ENVOY_HOSTNAME"
yq w -i ${TMPFILE} "static_resources.listeners[0].address.socket_address.port_value" "$ENVOY_PORT"

# Get sizes
TRITON_SERVERS_ARRAY_SIZE=${#TRITON_SERVERS_ARRAY[@]}

# Add GPU nodes as endpoints using yq
declare -i COUNTER
COUNTER=0

# Loop through all gpu nodes assigned to this LB task
for ((i=LB_ID; i<TRITON_SERVERS_ARRAY_SIZE; i+=N_LB)); do
    SERVER_ADDRESS=${TRITON_SERVERS_ARRAY[i]}
    yq w -i ${TMPFILE} "static_resources.clusters[0].load_assignment.endpoints[0].lb_endpoints[$COUNTER].endpoint.address.socket_address.address" "$SERVER_ADDRESS"
    yq w -i ${TMPFILE} "static_resources.clusters[0].load_assignment.endpoints[0].lb_endpoints[$COUNTER].endpoint.address.socket_address.port_value" "$TRITON_PORT"
    COUNTER+=1
done

echo "Generated config: $TMPFILE"
echo "Added $COUNTER Triton endpoints across assigned nodes"

# Run Envoy in Shifter container
shifter --module=none \
    --image=$LB_SHIFTER_IMAGE \
        envoy -c ${TMPFILE} --concurrency 16 \
              --disable-hot-restart

# Cleanup on exit
trap "rm -f ${TMPFILE}" EXIT