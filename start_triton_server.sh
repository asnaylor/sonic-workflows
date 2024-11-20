#!/usr/bin/env bash

set -x

TRITON_IMAGE=fastml/triton-torchgeo:22.07-py3-geometric
MODEL_DIR=$SCRATCH/cms/sonic/triton_models/CMSSW_14_1_0_pre7
LOG_DIR=$SCRATCH/cms/sonic/cmssw_14_1_0_pre7/Logs

#1 gpu each for 4 tritonservers
export TRITON_IMAGE
export MODEL_DIR
export LOG_DIR

srun \
    --ntasks-per-node=4 \
    --gpus-per-task=1 --cpus-per-task=32 \
    --label --output=$LOG_DIR/$(date +'%Y-%m-%d_%H-%M-%S')_triton_servers.log\
    bash -c 'shifter \
        --module=gpu \
        --image=$TRITON_IMAGE \
            tritonserver \
                --model-repository=$MODEL_DIR \
                --grpc-port $((8001 + $SLURM_LOCALID*10)) \
                --metrics-port $((8002 + $SLURM_LOCALID*10)) \
                --allow-http False \
                --log-verbose=3'