#!/usr/bin/env bash
#SBATCH --qos=regular
#SBATCH --time=08:00:00
#SBATCH --output="/pscratch/sd/a/asnaylor/cms/cmssw_14_1_X/logs/%j/slurm.log"

#SBATCH --image=cmssw/el7:x86_64
#SBATCH --module=cvmfs

#SBATCH --constraint='cpu'
#SBATCH --nodes=1


# Usage
# ./slurm_direct_cpu_job.sh <threads_per_client>


# Variables
SCRIPT_PATH="$(realpath "${BASH_SOURCE[0]}")"
MAIN_DIR=${SCRATCH}/cms/cmssw_14_1_X
LOG_DIR=${MAIN_DIR}/logs/${SLURM_JOBID}

N_CPU_NODES=${SLURM_JOB_NUM_NODES}
N_THREADS_PER_CLIENT=${1:-4}

CLIENT_SHIFTER_IMAGE=${SLURM_SPANK_SHIFTER_IMAGEREQUEST}

# Save metadata
mkdir -p ${LOG_DIR}
METADATA_FILE=${LOG_DIR}/config.txt
cp ${SCRIPT_PATH} ${LOG_DIR}/.
meta_vars=(
    "LOG_DIR"
    "N_CPU_NODES" "N_THREADS_PER_CLIENT"
    "CLIENT_SHIFTER_IMAGE"
) 

# Loop over the variable names and save them
> "$METADATA_FILE"  # clear file first
for var in "${meta_vars[@]}"; do
    value="${!var}"  # indirect expansion: get value of variable by name
    echo "$var=$value" >> "$METADATA_FILE"
done
echo "<> Metadata saved to $METADATA_FILE"

#Starting tests
echo "<> Starting tests..."

#Copy files to tmp
echo "[] Copy files to tmp"
srun \
    --label \
    --ntasks-per-node=1 \
        shifter \
            bash -c 'rm -rf /tmp/${USER}/*; mkdir -p /tmp/${USER}/dataset && \
                cp ${SCRATCH}/cms/dataset/{009E7EE3-3781-5048-A2F2-0E6139B13D46,015001B3-E5DC-154C-BE7C-CBEB4D2D5291,01918540-2DED-A54F-A3C4-C98845FB0C48}.root \
                /tmp/${USER}/dataset/.'

#Cache Run
N_TASKS=$((128 / ${N_THREADS_PER_CLIENT}))
echo "[] Start first cache run..."
mkdir ${LOG_DIR}/cache_run_1
srun \
    --time=00:20:00 \
    --cpus-per-task=${N_THREADS_PER_CLIENT} \
    --threads-per-core=1 \
    --ntasks-per-node=1 \
    --output=${LOG_DIR}/cache_run_1/sonic_client_%N_%t.out \
        shifter \
            ./shifter_cmsRun_nosonic.sh ${N_THREADS_PER_CLIENT} 100

#Cache Run
echo "[] Start second cache run..."
mkdir ${LOG_DIR}/cache_run_2
srun \
    --time=00:20:00 \
    --cpus-per-task=${N_THREADS_PER_CLIENT} \
    --threads-per-core=1 \
    --ntasks-per-node=1 \
    --output=${LOG_DIR}/cache_run_2/sonic_client_%N_%t.out \
        shifter \
                ./shifter_cmsRun_nosonic.sh ${N_THREADS_PER_CLIENT} 100


#Final Run
echo "[] Begin final run..."
mkdir ${LOG_DIR}/cmsRun
srun \
    --time=07:00:00 \
    --cpus-per-task=${N_THREADS_PER_CLIENT} \
    --threads-per-core=1 \
    --ntasks-per-node=${N_TASKS} \
    --output=${LOG_DIR}/%N_%t/sonic_client_%N_%t.out \
        shifter \
                ./shifter_cmsRun_nosonic.sh ${N_THREADS_PER_CLIENT} -1

#Clean up tmp
echo "[] Clean up tmp"
srun \
    --label \
    --ntasks-per-node=1 \
        shifter \
            bash -c 'rm -rf /tmp/${USER}/*'

echo "<> Complete"