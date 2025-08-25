#!/bin/bash

# Wait for healthy upstream endpoints from multiple Envoy proxy instances
# Usage: wait_for_envoy_upstreams.sh <admin_port> <envoy1> [envoy2] ...

TIMEOUT=${ENVOY_TIMEOUT:-300}
INTERVAL=${ENVOY_INTERVAL:-10}
START_TIME=$(date +%s)

if [ $# -eq 0 ]; then
    echo "Usage: $0 <admin_port> <envoy1> [envoy2] ..."
    exit 1
fi

ADMIN_PORT=${1}
ENVOY_PROXIES=("${@:2}")

echo "<> Checking Envoy upstream endpoints (timeout: ${TIMEOUT}s)..."

while true; do
    not_ready=()
    
    for proxy in "${ENVOY_PROXIES[@]}"; do
        # Check if this envoy proxy has healthy upstream endpoints
        healthy=$(curl -sf "http://${proxy}:${ADMIN_PORT}/clusters" 2>/dev/null | grep -c "health_flags::healthy" || echo 0)
        healthy=$(echo "$healthy" | tr -d '[:space:]')
        
        if [ "$healthy" -eq 0 ]; then
            not_ready+=("$proxy")
        fi
    done
    
    if [ ${#not_ready[@]} -eq 0 ]; then
        echo "<> All Envoy proxies have healthy upstream endpoints!"
        break
    fi
    
    elapsed=$(($(date +%s) - START_TIME))
    if [ $elapsed -ge $TIMEOUT ]; then
        echo "<> Timeout! Still waiting for healthy upstreams on: ${not_ready[*]}"
        exit 1
    fi
    
    echo "...Waiting for ${#not_ready[@]} proxy(ies) to have healthy upstreams (${elapsed}s/${TIMEOUT}s)"
    sleep $INTERVAL
done