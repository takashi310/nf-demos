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
params.mem_gb = 20
params.cpus = 8

// config for running on cluster
params.numWorkers = 8

include { getOptions } from '../utils' 

process define_dataset {
    container "janeliascicomp/n5-tools-py:1.1.0"
    containerOptions { getOptions([params.inputPath, params.outputPath, params.scriptPath]) }

    memory { "${params.mem_gb} GB" }
    cpus { 2 }

    input:
    tuple val(infile), val(outfile)

    output:
    val "${outfile}"
    
    script:
    """
    echo /nrs/scicompsoft/kawaset/nf-demos/entrypoint.sh define -i $infile -o $outfile -t 2 --verbose
    """
}

process fix_n5xml {
    container "janeliascicomp/n5-tools-py:1.1.0"
    containerOptions { getOptions([params.inputPath, params.outputPath, params.scriptPath]) }

    memory { "1 GB" }
    cpus { 1 }

    input:
    tuple val(infile), val(outfile)

    output:
    val "${outfile}"
    
    script:
    """
    echo /nrs/scicompsoft/kawaset/nf-demos/entrypoint.sh fix_n5xml -i $infile -o $outfile --verbose
    """
}

process background_subtraction {
    container "janeliascicomp/n5-tools-py:1.1.0"
    containerOptions { getOptions([params.inputPath, params.outputPath, params.scriptPath]) }

    memory { "${params.mem_gb} GB" }
    cpus { params.cpus }

    input:
    tuple val(bgfile), val(infile)

    output:
    val "${infile}"
    
    script:
    """
    echo /nrs/scicompsoft/kawaset/nf-demos/entrypoint.sh bg_sub -i $infile -b $bgfile -t ${params.cpus} --verbose
    """
}

process calc_stitching {
    container "janeliascicomp/n5-tools-py:1.1.0"
    containerOptions { getOptions([params.inputPath, params.outputPath, params.scriptPath]) }

    memory { "${params.mem_gb} GB" }
    cpus { params.cpus }

    input:
    val infile

    output:
    val "${infile}"
    
    script:
    """
    echo /nrs/scicompsoft/kawaset/nf-demos/entrypoint.sh calc_stitch -i $infile --verbose
    """
}

process copy_stitching_parameters {
    container "janeliascicomp/n5-tools-py:1.1.0"
    containerOptions { getOptions([params.inputPath, params.outputPath, params.scriptPath]) }

    memory { "1 GB" }
    cpus { 1 }

    input:
    val src
    tuple val(tar), val(out)

    output:
    val "${out}"
    
    script:
    """
    echo /nrs/scicompsoft/kawaset/nf-demos/entrypoint.sh copy_stitching_parameters -i $src -t $tar -o $out --verbose
    """
}

process copy_dims {
    container "janeliascicomp/n5-tools-py:1.1.0"
    containerOptions { getOptions([params.inputPath, params.outputPath, params.scriptPath]) }

    memory { "1 GB" }
    cpus { 1 }

    input:
    val src
    val tar

    output:
    val "${tar}"
    
    script:
    """
    echo /nrs/scicompsoft/kawaset/nf-demos/entrypoint.sh copy_dims -i $src -t $tar --verbose
    """
}


include { fusion as fusion_base; resave as resave_base; combine_n5 as combine_n5_base; fix_res as fix_res_base } from './reusables'
include { fusion as fusion_others; resave as resave_others; combine_n5 as combine_n5_others; fix_res as fix_res_others } from './reusables'

workflow {
    dir = params.inputPath
    outdir = params.outputPath
    baseimg = "${outdir}/${params.baseimg}"
    bgpath = params.bgimg

    println "output: ${params.baseimg}"

    myDir = file(outdir)
    result = myDir.mkdir()
    println result ? "OK" : "Cannot create directory: $myDir"

    bg = Channel.fromPath(bgpath).first()
    nd2 = Channel.fromPath("${dir}/*.nd2").toSortedList().flatten()
    nd2.subscribe { println "nd2: $it" }
    param = nd2.map{ tuple("$it", "${outdir}/${it.baseName}.xml") }
    n5xml = define_dataset(param)
    n5xml.subscribe { println "n5xml: $it" }

    param2 = n5xml.map{ tuple("$it", "${outdir}/${file(it).baseName}_fixed.xml") }
    fixedxml = fix_n5xml(param2)
    fixedxml.subscribe { println "fixedxml: $it" }

    param3 = fixedxml.map{ tuple(bgpath, "$it") }
    subtracted = background_subtraction(param3)
    subtracted.subscribe { println "subtracted: $it" }

    base_dataset_name = file(baseimg).getBaseName()
    base = subtracted.filter{ file -> ["${base_dataset_name}"].find { file.contains(it) } }
    others = subtracted.filter{ file -> ["${base_dataset_name}"].find { !file.contains(it) } }

    others.subscribe { println "others: $it" }

    calculated_base = calc_stitching(base)

    param4 = calculated_base.map{ tuple("$it", "${outdir}/${file(it).baseName}_fused_tmp.xml") }
    fused_base = fusion_base(param4)

    param5 = fused_base.map{ tuple("$it", "${outdir}/${file(it).baseName}_fused.xml") }
    resaved_base = resave_base(param5)

    src = calculated_base.first()
    param6 = others.map{ tuple("$it", "${outdir}/${file(it).baseName}_fused.xml") }
    copied_others = copy_stitching_parameters(src, param6)

    param7 = copied_others.map{ tuple("$it", "${outdir}/${file(it).baseName}_tmp.xml") }
    fused_others = fusion_others(param7)

    src2 = fused_base.first()
    copied_dims = copy_dims(src2, fused_others)

    param9 = copied_dims.map{ tuple("$it", "${outdir}/${file(it).baseName}_fused.xml") }
    resaved_others = resave_others(param9)

    zeroToNine = Channel.from( 0..9 )
    chmap = nd2.map{ "${outdir}/${it.baseName}_fixed_fused_tmp_fused.xml" }.merge(zeroToNine)
    resaved_base_with_ch = chmap.join(resaved_base)

    resaved_base_with_ch.subscribe { println "resaved_base_with_ch: $it" }

    dist8 = base.map{ "${outdir}/export.n5" }
    final_n5_base = combine_n5_base(resaved_base_with_ch, dist8, "--attr")
    fix_res_base(base, final_n5_base, "--base")

    resaved_others_with_ch = chmap.join(resaved_others)
    dist9 = others.map{ "${outdir}/export.n5" }
    final_n5_others = combine_n5_others(resaved_others_with_ch, dist9, "")
    fix_res_others(others, final_n5_others, "")

    resaved_others_with_ch.subscribe { println "resaved_others_with_ch: $it" }
}
