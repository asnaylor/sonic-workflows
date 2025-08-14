# SONIC workflows

This repository serves to deploy and run SONIC workflows for performance tests.

## Setup


### Install
```bash
mkdir -p $SCRATCH/cms/cmssw_14_1_X
cd $SCRATCH/cms/cmssw_14_1_X
source /cvmfs/cms.cern.ch/cmsset_default.sh
wget https://raw.githubusercontent.com/asnaylor/sonic-workflows/CMSSW_14_1_X/setup.sh
wget https://raw.githubusercontent.com/asnaylor/sonic-workflows/CMSSW_14_1_X/env.sh
chmod +x setup.sh
chmod +x env.sh
./setup.sh -j 16
```

### Each time
```bash
cd $SCRATCH/cms/cmssw_14_1_X
./env.sh
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

## Listing models

The following script provides a list of all models possibly used by a config:
```
./getModels.py --config step2_PAT
```
(Some of the listed models may not actually be used, depending on task and output configurations, but that can only be evaluated by fully executing the config.)
