#!/usr/bin/env bash

#Variables
LB_PORT=${1}
LB_ADDRESS="${@:2}"
LB_SERVERS_ARRAY=($LB_ADDRESS)
LB_INDEX=$(( SLURM_PROCID % ${#LB_SERVERS_ARRAY[@]} ))
ADDRESS=${LB_SERVERS_ARRAY[$LB_INDEX]}:${LB_PORT}
echo "<> Connecting to $ADDRESS" #remove

# Run enhanced baseline test with metrics collection
Second_dimension=100

# Each entry: "model_name extra_args"
MODEL_CONFIGS=(
    "deepmet -x 1"
    "deepmet -x 2"
    "deeptau_2017v2p1 --shape input_inner_egamma:11,11,86 \
                      --shape input_inner_muon:11,11,64 \
                      --shape input_inner_hadrons:11,11,38 \
                      --shape input_outer_egamma:21,21,86 \
                      --shape input_outer_muon:21,21,64 \
                      --shape input_outer_hadrons:21,21,38 "
    "deeptau_2018v2p5 --shape input_inner_egamma:11,11,86 \
                      --shape input_inner_muon:11,11,64 \
                      --shape input_inner_hadrons:11,11,38 \
                      --shape input_outer_egamma:21,21,86 \
                      --shape input_outer_muon:21,21,64 \
                      --shape input_outer_hadrons:21,21,38 "
    "particlenet_AK8_MassRegression_PT --shape pf_points__0:2,${Second_dimension} \
                                       --shape pf_features__1:25,${Second_dimension} \
                                       --shape pf_mask__2:1,${Second_dimension} \
                                       --shape sv_points__3:2,${Second_dimension} \
                                       --shape sv_features__4:11,${Second_dimension} \
                                       --shape sv_mask__5:1,${Second_dimension} "
    "particlenet_AK8_MD-2prong_PT --shape pf_points__0:2,${Second_dimension} \
                                       --shape pf_features__1:20,${Second_dimension} \
                                       --shape pf_mask__2:1,${Second_dimension} \
                                       --shape sv_points__3:2,${Second_dimension} \
                                       --shape sv_features__4:11,${Second_dimension} \
                                       --shape sv_mask__5:1,${Second_dimension} "
    "particleNetFromMiniAODAK4CHSCentral --shape pf_points:2,${Second_dimension} \
                                       --shape pf_features:41,${Second_dimension} \
                                       --shape pf_mask:1,${Second_dimension} \
                                       --shape sv_points:2,${Second_dimension} \
                                       --shape sv_features:10,${Second_dimension} \
                                       --shape sv_mask:1,${Second_dimension} \
                                       --shape lt_points:2,${Second_dimension} \
                                       --shape lt_features:19,${Second_dimension} \
                                       --shape lt_mask:1,${Second_dimension} "
    "particleNetFromMiniAODAK4PuppiCentral --shape pf_points:2,${Second_dimension} \
                                       --shape pf_features:41,${Second_dimension} \
                                       --shape pf_mask:1,${Second_dimension} \
                                       --shape sv_points:2,${Second_dimension} \
                                       --shape sv_features:10,${Second_dimension} \
                                       --shape sv_mask:1,${Second_dimension} \
                                       --shape lt_points:2,${Second_dimension} \
                                       --shape lt_features:19,${Second_dimension} \
                                       --shape lt_mask:1,${Second_dimension} "
    "particleNetFromMiniAODAK4PuppiForward --shape pf_points:2,${Second_dimension} \
                                       --shape pf_features:40,${Second_dimension} \
                                       --shape pf_mask:1,${Second_dimension} \
                                       --shape sv_points:2,${Second_dimension} \
                                       --shape sv_features:10,${Second_dimension} \
                                       --shape sv_mask:1,${Second_dimension} \
                                       --shape lt_points:2,${Second_dimension} \
                                       --shape lt_features:19,${Second_dimension} \
                                       --shape lt_mask:1,${Second_dimension} "
    "particleNetFromMiniAODAK8         --shape pf_points:2,${Second_dimension} \
                                       --shape pf_features:32,${Second_dimension} \
                                       --shape pf_mask:1,${Second_dimension} \
                                       --shape sv_points:2,${Second_dimension} \
                                       --shape sv_features:10,${Second_dimension} \
                                       --shape sv_mask:1,${Second_dimension} "
    "particlenet_PT                    --shape pf_points__0:2,${Second_dimension} \
                                       --shape pf_features__1:25,${Second_dimension} \
                                       --shape pf_mask__2:1,${Second_dimension} \
                                       --shape sv_points__3:2,${Second_dimension} \
                                       --shape sv_features__4:11,${Second_dimension} \
                                       --shape sv_mask__5:1,${Second_dimension} "
)


for CONFIG in "${MODEL_CONFIGS[@]}"
do
    # Split CONFIG into model name and extra args
    MODEL_NAME=$(awk '{print $1}' <<< "$CONFIG")
    EXTRA_ARGS=$(cut -d' ' -f2- <<< "$CONFIG")

    echo "<> Testing model: ${MODEL_NAME} with args ${EXTRA_ARGS}"

    for i in {0..4}
    do
        perf_analyzer -m ${MODEL_NAME} \
            -i grpc \
            -u ${ADDRESS} \
            --concurrency-range 1:1 \
            --measurement-interval 5000 \
            --stability-percentage 5 \
            --percentile 50:95:99 \
            --input-data random \
            -b 1 \
            ${EXTRA_ARGS}
    done
done

echo "<> Perf_analyzer test complete"