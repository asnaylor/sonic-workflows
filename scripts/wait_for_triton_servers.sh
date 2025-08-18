#!/bin/bash

# Wait for Triton servers to be ready
# Usage: wait_for_triton_servers.sh server1:port server2:port ...

TIMEOUT=${TRITON_TIMEOUT:-300}
INTERVAL=${TRITON_INTERVAL:-20}
START_TIME=$(date +%s)

if [ $# -eq 0 ]; then
    echo "Usage: $0 <server1:port> [server2:port] ..."
    exit 1
fi

GPU_SERVERS=("$@")

echo "<> Checking Triton servers (timeout: ${TIMEOUT}s)..."

while true; do
    not_ready=()
    
    for server in "${GPU_SERVERS[@]}"; do
        if ! curl -sf -m 5 "http://${server}/v2/health/ready" > /dev/null 2>&1; then
            not_ready+=("$server")
        fi
    done
    
    if [ ${#not_ready[@]} -eq 0 ]; then
        echo "<> All servers ready!"
        break
    fi
    
    elapsed=$(($(date +%s) - START_TIME))
    if [ $elapsed -ge $TIMEOUT ]; then
        echo "<> Timeout! Still waiting for: ${not_ready[*]}"
        exit 1
    fi
    
    echo "...Waiting for ${#not_ready[@]} server(s) (${elapsed}s/${TIMEOUT}s)"
    sleep $INTERVAL
done