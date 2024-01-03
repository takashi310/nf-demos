#!/usr/bin/env nextflow

nextflow.enable.dsl=2

// path to the TIFF series
params.inputPath = ""

// path to the output n5
params.outputPath = ""

params.baseimg = ""

params.bgimg = "/nrs/scicompsoft/kawaset/Liu/AVG_DarkFrameStandardMode50ms.tif"

// path to the scripts
params.scriptPath = "/nrs/scicompsoft/kawaset/nf-demos"

// path to the output dataset
params.outputDataset = "/s0"

// chunk size for n5
params.blockSize = "512,512,256"

// config for running single process
params.mem_gb = 440
params.cpus = 48

// config for running on cluster
params.numWorkers = 8

params.timeNum = 5

params.spark_local_dir = null
params.spark_cluster = true
params.spark_workers = 1
params.spark_worker_cores = 4
params.spark_gb_per_core = 4
params.spark_driver_cores = 1
params.spark_driver_memory = '1 GB'

include { getOptions } from '../utils' 

include { SPARK_START         } from '../subworkflows/bits/spark_start/main'
include { SPARK_STOP          } from '../subworkflows/bits/spark_stop/main'

process define_dataset {
    container "janeliascicomp/n5-tools-py:1.1.0"
    containerOptions { getOptions([params.inputPath, params.outputPath, params.scriptPath]) }

    memory { "4 GB" }
    cpus { 1 }

    input:
    tuple val(infile), val(outfile)

    output:
    val "${outfile}"
    
    script:
    """
    echo /nrs/scicompsoft/kawaset/nf-demos/entrypoint.sh define -i $infile -o $outfile -t 2 > /dev/null 2>&1
    """
}

process fix_n5xml {
    container "janeliascicomp/n5-tools-py:1.1.0"
    containerOptions { getOptions([params.inputPath, params.outputPath, params.scriptPath]) }

    memory { "4 GB" }
    cpus { 1 }

    input:
    tuple val(infile), val(outfile)

    output:
    val "${outfile}"
    
    script:
    """
    echo /nrs/scicompsoft/kawaset/nf-demos/entrypoint.sh fix_n5xml -i $infile -o $outfile > /dev/null 2>&1
    """
}

process background_subtraction {
    container "janeliascicomp/n5-tools-py:1.1.0"
    containerOptions { getOptions([params.inputPath, params.outputPath, params.scriptPath]) }

    memory { "600 GB" }
    cpus { 48 }

    input:
    tuple val(bgfile), val(infile)

    output:
    val "${infile}"
    
    script:
    """
    echo /nrs/scicompsoft/kawaset/nf-demos/entrypoint.sh bg_sub -i $infile -b $bgfile -t ${params.cpus}
    """
}
/*
process calc_stitching {
    container "janeliascicomp/n5-tools-py:1.1.0"
    containerOptions { getOptions([params.inputPath, params.outputPath, params.scriptPath]) }

    memory { "600 GB" }
    cpus { 48 }

    input:
    val infile

    output:
    val "${infile}"
    
    script:
    """
    echo /nrs/scicompsoft/kawaset/nf-demos/entrypoint.sh calc_stitch -i $infile > /dev/null 2>&1
    """
}
*/
process calc_stitching {
    container "janeliascicomp/n5-tools-py:1.1.0"
    containerOptions { getOptions([params.inputPath, params.outputPath, params.scriptPath]) }

    memory { "600 GB" }
    cpus { 48 }

    input:
    tuple val(meta), path(files), val(spark)

    output:
    tuple val(meta), path(files), val(spark), emit: acquisitions
    
    script:
    """
    echo /nrs/scicompsoft/kawaset/nf-demos/entrypoint.sh calc_stitch -i $files > /dev/null 2>&1
    """
}


process mvdir {
    container "janeliascicomp/n5-tools-py:1.1.0"
    containerOptions { getOptions([params.inputPath, params.outputPath, params.scriptPath]) }

    memory { "4 GB" }
    cpus { 1 }

    input:
    tuple val(input), val(output)

    output:
    val "${output}"
    
    script:
    """
    mv $input $output
    """
}

process copy_stitching_parameters {
    container "janeliascicomp/n5-tools-py:1.1.0"
    containerOptions { getOptions([params.inputPath, params.outputPath, params.scriptPath]) }

    memory { "4 GB" }
    cpus { 1 }

    input:
    val src
    tuple val(tar), val(out)

    output:
    val "${out}"
    
    script:
    """
    echo /nrs/scicompsoft/kawaset/nf-demos/entrypoint.sh copy_stitching_parameters -i $src -t $tar -o $out
    """
}

process copy_dims {
    container "janeliascicomp/n5-tools-py:1.1.0"
    containerOptions { getOptions([params.inputPath, params.outputPath, params.scriptPath]) }

    memory { "4 GB" }
    cpus { 1 }

    input:
    val src
    val tar

    output:
    val "${tar}"
    
    script:
    """
    echo /nrs/scicompsoft/kawaset/nf-demos/entrypoint.sh copy_dims -i $src -t $tar
    """
}

process gen_csv {
    container "janeliascicomp/n5-tools-py:1.1.0"
    containerOptions { getOptions([params.inputPath, params.outputPath, params.scriptPath]) }

    memory { "4 GB" }
    cpus { 1 }

    input:
    tuple val(src), val(tar)

    output:
    val "${tar}"
    
    script:
    """
    echo /nrs/scicompsoft/kawaset/nf-demos/entrypoint.sh nd2tiffcsv -i $src -o $tar
    """
}

process split_xml {
    container "janeliascicomp/n5-tools-py:1.1.0"
    containerOptions { getOptions([params.inputPath, params.outputPath, params.scriptPath]) }

    memory { "4 GB" }
    cpus { 1 }

    input:
    tuple val(src), val(tar), val(csv)

    output:
    val "${csv}"
    
    script:
    """
    echo /nrs/scicompsoft/kawaset/nf-demos/entrypoint.sh nd2tiffxml -i $src -o $tar -c $csv
    """
}

process nd2tiff {
    container "janeliascicomp/n5-tools-py:1.1.0"
    containerOptions { getOptions([params.inputPath, params.outputPath, params.scriptPath]) }

    memory { "16 GB" }
    cpus { 1 }

    input:
    tuple val(src), val(tar), val(bg)

    output:
    val("process_complete"), emit: control_1
    
    script:
    """
    echo /nrs/scicompsoft/kawaset/nf-demos/entrypoint.sh nd2tiff -i $src -o $tar -b $bg
    """
}

process STITCHING_PREPARE {
    tag "${meta.id}"
    label 'process_single'

    input:
    tuple val(meta), path(files)

    output:
    tuple val(meta), path(files)

    script:
    """
    umask 0002
    mkdir -p ${meta.spark_work_dir}
    """
}

process SPARK_RESAVE {
    tag "${meta.id}"
    container 'docker.io/multifish/biocontainers-stitching-spark:1.9.0'
    cpus { spark.driver_cores }
    memory { spark.driver_memory }

    input:
    tuple val(meta), path(xml), val(spark)
    val(control_1) 

    output:
    tuple val(meta), path(xml), val(spark), emit: acquisitions
    path "versions.yml", emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    extra_args = task.ext.args ?: ''
    executor_memory = spark.executor_memory.replace(" KB",'k').replace(" MB",'m').replace(" GB",'g').replace(" TB",'t')
    driver_memory = spark.driver_memory.replace(" KB",'k').replace(" MB",'m').replace(" GB",'g').replace(" TB",'t')
    outxml = meta.outxml
    n5dir = meta.outxml
    """
    echo /opt/scripts/runapp.sh "$workflow.containerEngine" "$spark.work_dir" "$spark.uri" \
        /app/app.jar net.preibisch.bigstitcher.spark.ResaveN5 \
        $spark.parallelism $spark.worker_cores "$executor_memory" $spark.driver_cores "$driver_memory" \
        -x ${xml} -xo ${outxml} -o ${n5dir} --blockSize 512,512,128 -ds 1,1,1

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        spark: \$(cat /opt/spark/VERSION)
        stitching-spark: \$(cat /app/VERSION)
    END_VERSIONS
    """
}

process SPARK_FUSION {
    tag "${meta.id}"
    container 'docker.io/multifish/biocontainers-stitching-spark:1.9.0'
    cpus { spark.driver_cores }
    memory { spark.driver_memory }

    input:
    tuple val(meta), path(xml), val(spark) 

    output:
    tuple val(meta), path(xml), val(spark), emit: acquisitions
    path "versions.yml", emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    extra_args = task.ext.args ?: ''
    executor_memory = spark.executor_memory.replace(" KB",'k').replace(" MB",'m').replace(" GB",'g').replace(" TB",'t')
    driver_memory = spark.driver_memory.replace(" KB",'k').replace(" MB",'m').replace(" GB",'g').replace(" TB",'t')
    outxml = meta.outxml
    n5dir = meta.outxml
    """
    echo /opt/scripts/runapp.sh "$workflow.containerEngine" "$spark.work_dir" "$spark.uri" \
        /app/app.jar net.preibisch.bigstitcher.spark.AffineFusion \
        $spark.parallelism $spark.worker_cores "$executor_memory" $spark.driver_cores "$driver_memory" \
        --bdv -x ${xml} -xo ${outxml} -o ${n5dir} --blockSize 512,512,128 -ds 2,2,1; 2,2,2; 2,2,2; 2,2,2

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        spark: \$(cat /opt/spark/VERSION)
        stitching-spark: \$(cat /app/VERSION)
    END_VERSIONS
    """
}

include { fusion as fusion; resave_t as resave_time; combine_n5 as combine_n5_base; fix_res as fix_res } from './reusables'
include { fusion as fusion_others; resave as resave; combine_n5 as combine_n5_others; fix_res as fix_res_others } from './reusables'

workflow {
    infile = params.inputPath
    indir = file(params.inputPath).parent
    outdir = params.outputPath
    baseimg = "${outdir}/${params.baseimg}"
    bgpath = params.bgimg

    println "output: ${params.baseimg}"

    myDir = file(outdir)
    result = myDir.mkdir()
    println result ? "OK" : "Cannot create directory: $myDir"

    bg = Channel.fromPath(bgpath).first()
    nd2 = Channel.fromPath(infile)
    base_name = file(infile).getBaseName()
    timeIDs = Channel.from( 0..(params.timeNum-1) )
    nd2.subscribe { println "nd2: $it" }

    param_t = nd2.map{ tuple("${infile}", "${outdir}/${file(it).baseName}.csv") }
    csv = gen_csv(param_t)
    csv.subscribe { println "csv: $it" }

    csv
    .map { file(it) }
    .set { csvfile }

    csvfile
    .splitCsv(header:false)
    .map { row-> row[0] }
    .set { flist }

    param_tif = flist.map{ tuple("${infile}", "${it}", "${bgpath}") }
    tiff1 = nd2tiff(param_tif).first()
    tiff1.subscribe { println "tiff1: $it" }
    
    param = nd2.map{ tuple("${infile}", "${outdir}/${file(it).baseName}.xml") }
    n5xml = define_dataset(param)
    n5xml.subscribe { println "n5xml: $it" }

    param2 = n5xml.map{ tuple("$it", "${outdir}/${file(it).baseName}_fixed.xml") }
    fixedxml = fix_n5xml(param2)
    fixedxml.subscribe { println "fixedxml: $it" }

    param_t = fixedxml.map{ tuple("$it", "${outdir}/${file(it).baseName}_tiff.xml", "${outdir}/${file(it).baseName}_tiff.csv") }
    csv2 = split_xml(param_t)
    csv2.subscribe { println "csv2: $it" }

    csv2
    .map { file(it) }
    .set { csvfile2 }

    csvfile2
    .splitCsv(header:false)
    .map { row-> row[0] }
    .set { flist2 }

    flist2.subscribe { println "flist2: $it" }

    flist2.map {
        def xml = it
        meta = [:]
        meta.id = file(xml).baseName
        // set output subdirectories for each acquisition
        meta.spark_work_dir = "${outdir}/spark/${workflow.sessionId}/${meta.id}"
        meta.outdir = outdir
        meta.outxml = meta.outdir + "/" + meta.id + "_resaved.xml"
        meta.n5dir = meta.outdir + "/" + meta.id + "_resaved.n5"
        [meta, xml]
    }.set { ch_acquisitions }

    STITCHING_PREPARE(
        ch_acquisitions
    )

    SPARK_START(
        STITCHING_PREPARE.out, 
        [indir, outdir], //directories to mount
        params.spark_cluster,
        params.spark_workers as int,
        params.spark_worker_cores as int,
        params.spark_gb_per_core as int,
        params.spark_driver_cores as int,
        params.spark_driver_memory
    )

    SPARK_RESAVE(SPARK_START.out, nd2tiff.out.control_1.collect())

    //param3 = flist2.map{ tuple("${it}", "${outdir}/${file(it).baseName}_rs.xml") }
    //resaved_times = resave(param3, nd2tiff.out.control_1.collect())
    //resaved_times.subscribe { println "resaved_times: $it" }

    //param3b = SPARK_RESAVE.out.acquisitions.map{ "${outdir}/${file(it[1]).baseName}.xml" }
    //calculated = calc_stitching(param3b)
    calc_stitching(SPARK_RESAVE.out.acquisitions)

    //param4 = calculated.map{ tuple("$it", "${outdir}/${file(it).baseName}_fused.xml") }
    //fused = fusion(param4)
    //fused.subscribe { println "fused: $it" }
    SPARK_FUSION(calc_stitching.out.acquisitions)

    done = SPARK_STOP(SPARK_FUSION.out.acquisitions)

    param5 = SPARK_FUSION.out.acquisitions.map{ tuple("${it[1]}", "${outdir}/easi") }
    moved = fix_res(param5)
    moved.subscribe { println "moved: $it" }

    //param5 = fused.map{ tuple("$it", "${outdir}/${file(it).baseName}_n5.xml") }
    //resaved2 = resave(param5)
    //resaved2.subscribe { println "resaved2: $it" }

    //param6 = fused.map{ tuple("$it", "${outdir}/${file(it).baseName}_n5.xml") }
}
