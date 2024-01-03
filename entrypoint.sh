#!/bin/bash
source /opt/conda/etc/profile.d/conda.sh
SCRIPT_NAME=$1; shift
conda activate myenv
python /nrs/scicompsoft/kawaset/nf-demos/containers/n5-tools-py/scripts/${SCRIPT_NAME}.py "$@"