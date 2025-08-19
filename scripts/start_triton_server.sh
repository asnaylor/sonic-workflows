#!/usr/bin/env bash

set -x

TRITON_SHIFTER_IMAGE=$1
MODEL_DIR=$2

shifter --module=gpu --image=${TRITON_SHIFTER_IMAGE} \
    tritonserver \
        --model-repository=${MODEL_DIR} \
        --grpc-address ${HOSTNAME}-hsn${SLURM_LOCALID} \
        --grpc-port 8001 \
        --http-port $((8000 + $SLURM_LOCALID*10)) \
        --metrics-port $((8002 + $SLURM_LOCALID*10))