#!/bin/bash

export PATH="/groups/scicompsoft/home/kawaset:$PATH"
source /groups/scicompsoft/home/kawaset/miniconda3/etc/profile.d/conda.sh
conda activate octree
cd /nrs/scicompsoft/kawaset/nf-demos

export JAVA_HOME=${HOME}/tools/jdk-17

DIR=$(cd "$(dirname "$0")"; pwd)
BASEDIR=$(realpath $DIR/..)

# The temporary directory needs to have 10 GB to store large Docker images
export TMPDIR="${TMPDIR:-/tmp}"
export SINGULARITY_TMPDIR="${SINGULARITY_TMPDIR:-$TMPDIR}"
export SINGULARITY_CACHEDIR="${SINGULARITY_CACHEDIR:-$TMPDIR/singularity}"
mkdir -p $TMPDIR
mkdir -p $SINGULARITY_TMPDIR
mkdir -p $SINGULARITY_CACHEDIR

datadir=$(realpath $1)
shift # eat the first argument so that $@ works later

#/nrs/scicompsoft/kawaset/Liu/nextflow run /nrs/scicompsoft/kawaset/nf-demos/nd2n5/nd2n5.nf -profile lsf -process.echo --runtime_opts "--env TMPDIR=/scratch/kawaset -B /nrs/scicompsoft/kawaset -B /groups/scicompsoft/home/kawaset -B /scratch" --inputPath '/nrs/scicompsoft/kawaset/Liu2' --outputPath '/nrs/scicompsoft/kawaset/Liu2/output' --baseimg 'Channel488_Seq0002.nd2' --bgimg '/nrs/scicompsoft/kawaset/Liu2/AVG_DarkFrameStandardMode50ms.tif'

#/nrs/scicompsoft/kawaset/Liu/nextflow run /nrs/scicompsoft/kawaset/nf-demos/nd2n5/nd2n5.nf -process.echo

#/nrs/scicompsoft/kawaset/Liu/nextflow run ./nd2n5/nd2n5-cp.nf --inputPath '/nrs/scicompsoft/kawaset/Liu' --outputPath '/nrs/scicompsoft/kawaset/Liu/output' --baseimg 'Channel488.nd2' --bgimg '/nrs/scicompsoft/kawaset/Liu/AVG_DarkFrameStandardMode50ms.tif' -process.echo

/nrs/scicompsoft/kawaset/Liu/nextflow run /nrs/scicompsoft/kawaset/nf-demos/nd2n5/nd2n5.nf -profile lsf -process.echo --runtime_opts "--env PATH="/groups/scicompsoft/home/kawaset/tools/jdk-17/bin:\$PATH" --env JAVA_HOME=/groups/scicompsoft/home/kawaset/tools/jdk-17 --env TMPDIR=/scratch/kawaset -B /misc/sc/jdks/ -B /nrs/scicompsoft/kawaset -B /groups/scicompsoft/home/kawaset -B /scratch" --inputPath '/nrs/scicompsoft/kawaset/Liu3/40X_cereb_11genes/Channel640_561_488_405_Seq0000.nd2' --outputPath '/nrs/scicompsoft/kawaset/Liu3/output_tif' --bgimg '/nrs/scicompsoft/kawaset/Liu3/40X_cereb_11genes/AVG_DarkFrameFastMode20ms.tif'