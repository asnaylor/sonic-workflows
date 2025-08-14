#!/usr/bin/env bash
SHIFTER_IMAGE="cmssw/el7:x86_64"

shifter --image=${SHIFTER_IMAGE} --module=cvmfs \
	/bin/bash -c "
		  source /cvmfs/cms.cern.ch/cmsset_default.sh && \
		  cd CMSSW_14_1_0_pre7/src/ && \
		  cmsenv && \
		  cd sonic-workflows && \
		  exec /bin/bash "
