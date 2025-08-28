#!/usr/bin/env bash

echo "Job started at: $(date)"

cleanup() {
    echo "[$(date)] Caught SIGTERM!"
    echo "Contents of ${TMP_OUT}:"
	echo "--------"
    cat ${TMP_OUT}
	echo "--------"
    echo "Killing cmsRun process ($CMSRUN_PID)"
    kill $CMSRUN_PID 2>/dev/null
    wait $CMSRUN_PID 2>/dev/null
    rm ${TMP_OUT}
    echo "Exiting"
    exit 1
}

trap cleanup TERM

#Variables
N_THREADS=$1
MAX_EVENTS=$2

#Initalise
source /cvmfs/cms.cern.ch/cmsset_default.sh
cd ../../
cmsenv
cd sonic-workflows

#Run
echo "Running ${MAX_EVENTS} evts with ${N_THREADS} threads"

RND=$(uuidgen | cut -c1-6)
TMP_OUT=/tmp/${USER}/${RND}_sonic.log
time cmsRun run.py \
	 --threads ${N_THREADS} \
	 --maxEvents ${MAX_EVENTS} \
	 --noSonic \
     --verbose  \
	 --tmi &> ${TMP_OUT} &

CMSRUN_PID=$!
wait $CMSRUN_PID

grep -A 20 "TimeReport> Time report complete" ${TMP_OUT}
rm ${TMP_OUT}
