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

include { getOptions } from '../utils' 

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
    /nrs/scicompsoft/kawaset/nf-demos/entrypoint.sh bg_sub -i $infile -b $bgfile -t ${params.cpus}
    """
}

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
    /nrs/scicompsoft/kawaset/nf-demos/entrypoint.sh copy_stitching_parameters -i $src -t $tar -o $out
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
    /nrs/scicompsoft/kawaset/nf-demos/entrypoint.sh copy_dims -i $src -t $tar
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


include { fusion as fusion; resave_t as resave_time; combine_n5 as combine_n5_base; fix_res as fix_res } from './reusables'
include { fusion as fusion_others; resave as resave; combine_n5 as combine_n5_others; fix_res as fix_res_others } from './reusables'

workflow {
    infile = params.inputPath
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

    param3 = flist2.map{ tuple("${it}", "${outdir}/${file(it).baseName}_rs.xml") }
    resaved_times = resave(param3, nd2tiff.out.control_1.collect())
    resaved_times.subscribe { println "resaved_times: $it" }

    //param4 = resaved_times.map{ tuple(bgpath, "${outdir}/${file(it).baseName}.xml") }
    //subtracted = background_subtraction(param4)
    //subtracted.subscribe { println "subtracted: $it" }

    param3b = resaved_times.map{ "${outdir}/${file(it).baseName}.xml" }
    calculated = calc_stitching(param3b)

    param4 = calculated.map{ tuple("$it", "${outdir}/${file(it).baseName}_fused.xml") }
    fused = fusion(param4)
    fused.subscribe { println "fused: $it" }

    param5 = fused.map{ tuple("$it", "${outdir}/easi") }
    moved = fix_res(param5)
    moved.subscribe { println "moved: $it" }

    //param5 = fused.map{ tuple("$it", "${outdir}/${file(it).baseName}_n5.xml") }
    //resaved2 = resave(param5)
    //resaved2.subscribe { println "resaved2: $it" }

    //param6 = fused.map{ tuple("$it", "${outdir}/${file(it).baseName}_n5.xml") }
}
