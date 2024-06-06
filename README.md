# SONIC workflows

This repository serves to deploy and run SONIC workflows for performance tests at NERSC.

## Setup
```bash
#Run inside apptainer from cvmfs
source /cvmfs/cms.cern.ch/cmsset_default.sh 
export PATH=/cvmfs/oasis.opensciencegrid.org/mis/apptainer/current/bin:$PATH
cmssw-el7 --nv --bind $SCRATCH
wget https://raw.githubusercontent.com/asnaylor/sonic-workflows/master/setup.sh
chmod +x setup.sh
./setup.sh
cd CMSSW_12_0_0_pre5/src/sonic-workflows
cmsenv
```

## Running
```bash
cmsRun run.py
```

To run the Run-3 workflow, change it to 
```bash
cmsRun run.py config=step4_PAT_Run3
```