#!/usr/bin/env bash

function step1() {
    ctxedr2lev1eo.sh $1
    if [ $? -eq 0 ]
    then
        echo "Success ctxedr2lev1eo on $(date). (1/4)"
    else
        echo "Failure ctxedr2lev1eo on $(date). (1/4)" >&2
        exit 1
    fi
}

function step2() {
    asp_ctx_lev1eo2dem.sh -s $1 -p $2
    if [ $? -eq 0 ]
    then
        echo "Success asp_ctx_lev1eo2dem on $(date). (2/4)"
    else
        echo "Failure asp_ctx_lev1eo2dem on $(date). (2/4)" >&2
        exit 1
    fi
}

function step3() {
    asp_ctx_step2_map2dem.sh -s $1 -p $2
    if [ $? -eq 0 ]
    then
        echo "Success asp_ctx_step2_map2dem on $(date). (3/4)"
    else
        echo "Failure asp_ctx_step2_map2dem on $(date). (3/4)" >&2
        exit 1
    fi
}

function step4() {
    pedr_bin4pc_align.sh $1
    if [ $? -eq 0 ]
    then
        echo "Success pedr_bin4pc_align on $(date). (4/4)"
    else
        echo "Failure pedr_bin4pc_align on $(date). (4/4)" >&2
        exit 1
    fi
}

print_usage (){
    echo ""
    echo "Usage: $0 <stereo.default> <productIDs.lis> <pedr_list.lis>"
    echo " Where <stereo.default> is the name and absolute path to the stereo.default file to be used by the stereo command."
    echo " Where <productIDs.lis> is a file containing a list of the IDs of the CTX products to be processed."
    echo " Where <pedr_list.lis> is a file containing a list of the MOLA PEDR binary files to search through, including absolute path."
    echo "       <pedr_list.lis> itself should should be specified using the absolute path to its location."
    echo "       This file is required by pedr2tab."
    echo ""
}

##########################################
# begin parsing arguments
# todo: work out a way to pass in two stereo files, possibly by checking for 4 args
# https://stackoverflow.com/questions/13361658/how-to-presence-detect-a-positional-parameter-in-bash

# 1 is stereo.default file
# 2 is productIDs file
# 3 is pedr_list file

### Check for the correct number of args and hope for the best ###
if [[ $# != 3 ]] ; then
    # print usage message and exit
    print_usage
    exit 0
fi

##########################################
# begin calling commands
echo "Start ctx_pipeline_part_one $(date)"

step1 $2

step2 $1 $2

step3 $1 $2

step4 $3

# done
##########################################
echo "End   ctx_pipeline_part_one $(date)"