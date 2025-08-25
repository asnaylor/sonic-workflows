#!/usr/bin/env bash
#SBATCH --qos=regular
#SBATCH --time=08:00:00
#SBATCH --output="/pscratch/sd/a/asnaylor/cms/cmssw_14_1_X/logs/%j/slurm.log"

#SBATCH --image=cmssw/el7:x86_64
#SBATCH --module=cvmfs

#SBATCH --constraint='gpu&hbm40g'
#SBATCH --nodes=1
#SBATCH hetjob
#SBATCH --constraint='gpu&hbm40g'
#SBATCH --nodes=1
#SBATCH hetjob
#SBATCH --constraint='cpu'
#SBATCH --nodes=1

# Het group 0 - Triton
# Het group 1 - Load Balancer
# Het group 2 - Client

# Usage
# ./slurm_iaas_job.sh <threads_per_client>


# Variables
SCRIPT_PATH="$(realpath "${BASH_SOURCE[0]}")"
MAIN_DIR=${SCRATCH}/cms/cmssw_14_1_X
LOG_DIR=${MAIN_DIR}/logs/${SLURM_JOBID}
MODEL_DIR=$SCRATCH/cms/sonic/triton_models/CMSSW_14_1_0_pre7_LATEST

N_GPU_NODES=${SLURM_JOB_NUM_NODES_HET_GROUP_0}
N_LB_NODES=${SLURM_JOB_NUM_NODES_HET_GROUP_1}
N_CPU_NODES=${SLURM_JOB_NUM_NODES_HET_GROUP_2}
N_THREADS_PER_CLIENT=${1:-4}

TRITON_SHIFTER_IMAGE="fastml/triton-torchgeo:22.07-py3-geometric"
LB_SHIFTER_IMAGE="envoyproxy/envoy:v1.34.0"
CLIENT_SHIFTER_IMAGE=${SLURM_SPANK_SHIFTER_IMAGEREQUEST}

# Save metadata
mkdir -p ${LOG_DIR}
METADATA_FILE=${LOG_DIR}/config.txt
cp ${SCRIPT_PATH} ${LOG_DIR}/.
meta_vars=(
    "LOG_DIR" "MODEL_DIR"
    "N_GPU_NODES" "N_LB_NODES" "N_CPU_NODES" "N_THREADS_PER_CLIENT"
    "TRITON_SHIFTER_IMAGE" "LB_SHIFTER_IMAGE" "CLIENT_SHIFTER_IMAGE"
) 

# Loop over the variable names and save them
> "$METADATA_FILE"  # clear file first
for var in "${meta_vars[@]}"; do
    value="${!var}"  # indirect expansion: get value of variable by name
    echo "$var=$value" >> "$METADATA_FILE"
done
echo "<> Metadata saved to $METADATA_FILE"

# Launch Triton
echo "<> Starting $((4*N_GPU_NODES)) Triton servers"
mkdir ${LOG_DIR}/triton
srun \
    --het-group=0 \
    --ntasks-per-node=4 \
    --gpus-per-task=1 --gpu-bind=closest --cpus-per-task=16 --threads-per-core=1 \
    --output=${LOG_DIR}/triton/triton_GPU_server_%N_%t.out \
        ./start_triton_server.sh ${TRITON_SHIFTER_IMAGE} ${MODEL_DIR} &
GPU_NODELIST=($(scontrol show hostnames ${SLURM_JOB_NODELIST_HET_GROUP_0}))

# Triton Health Check
ports=(8000 8010 8020 8030)

# Convert to array
GPU_SERVERS=()
for node in "${GPU_NODELIST[@]}"; do
    for port in "${ports[@]}"; do
        GPU_SERVERS+=("${node}:${port}")
    done
done

#Wait for triton servers to start
./wait_for_triton_servers.sh "${GPU_SERVERS[@]}"

# Convert GPU Nodes to triton server ips
gpu_nics=("hsn0" "hsn1" "hsn2" "hsn3")

# Convert to array
TRITON_SERVERS=()
for node in "${GPU_NODELIST[@]}"; do
    for nic in "${gpu_nics[@]}"; do
        TRITON_SERVERS+=("$(dig +short ${node}-${nic})")
    done
done

# Launch Load Balancers
echo "<> Starting $((4*N_LB_NODES)) LBs"
mkdir ${LOG_DIR}/envoy
srun \
    --het-group=1 \
    --ntasks-per-node=4 \
    --gpus-per-task=1 --gpu-bind=closest --cpus-per-task=16 --threads-per-core=1 \
    --output=${LOG_DIR}/envoy/envoy_server_%N_%t.out \
        ./start_envoy_proxy.sh ${LB_SHIFTER_IMAGE} ${N_LB_NODES} "${TRITON_SERVERS[@]}" &

LB_NODELIST=($(scontrol show hostnames ${SLURM_JOB_NODELIST_HET_GROUP_1}))

# Convert to array
LB_SERVERS=()
LB_PORT=9000
for node in "${LB_NODELIST[@]}"; do
    for nic in "${gpu_nics[@]}"; do
        LB_SERVERS+=("$(dig +short ${node}-${nic})")
    done
done

#wait for lb
sleep 60

# Launch Test with perf_analyzer
echo "<> Perf analyzer test"
srun \
    --label \
    --het-group=2 \
    --time=00:20:00 \
    --ntasks-per-node=1 \
        shifter \
        --image=nvcr.io/nvidia/tritonserver:22.02-py3-sdk --module=none \
                ./perf_analyzer_test.sh ${LB_PORT} "${LB_SERVERS[@]}"


#N_THREADS_PER_CLIENT