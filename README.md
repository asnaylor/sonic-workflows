# SONIC workflows

This repository serves to deploy and run SONIC workflows for performance tests.

## Setup
```bash
#Run inside apptainer from cvmfs
source /cvmfs/cms.cern.ch/cmsset_default.sh 
export PATH=/cvmfs/oasis.opensciencegrid.org/mis/apptainer/current/bin:$PATH
cmssw-el7 --nv --bind $SCRATCH
wget https://raw.githubusercontent.com/asnaylor/sonic-workflows/CMSSW_14_1_X/setup.sh
chmod +x setup.sh
./setup.sh
cd CMSSW_14_1_0_pre0/src/sonic-workflows
cmsenv
```

## Running

To see the available options:
```bash
cmsRun run.py --help
```

To run a workflow with the default settings:
```bash
cmsRun run.py --maxEvents 100
```