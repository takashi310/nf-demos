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
params.mem_gb = 220
params.cpus = 16

// config for running on cluster
params.numWorkers = 8

include { getOptions } from '../utils' 

process define_dataset {
    container "janeliascicomp/n5-tools-py:1.1.0"
    containerOptions { getOptions([params.inputPath, params.outputPath, params.scriptPath]) }

    memory { "${params.mem_gb} GB" }
    cpus { 2 }

    input:
    val infile
    val outfile

    output:
    val "${outfile}"
    
    script:
    """
    /nrs/scicompsoft/kawaset/nf-demos/entrypoint.sh define -i $infile -o $outfile -t 2 --verbose
    """
}

process fix_n5xml {
    container "janeliascicomp/n5-tools-py:1.1.0"
    containerOptions { getOptions([params.inputPath, params.outputPath, params.scriptPath]) }

    memory { "1 GB" }
    cpus { 1 }

    input:
    val infile
    val outfile

    output:
    val "${outfile}"
    
    script:
    """
    /nrs/scicompsoft/kawaset/nf-demos/entrypoint.sh fix_n5xml -i $infile -o $outfile --verbose
    """
}

process background_subtraction {
    container "janeliascicomp/n5-tools-py:1.1.0"
    containerOptions { getOptions([params.inputPath, params.outputPath, params.scriptPath]) }

    memory { "${params.mem_gb} GB" }
    cpus { params.cpus }

    input:
    val bgfile
    val infile

    output:
    val "${infile}"
    
    script:
    """
    /nrs/scicompsoft/kawaset/nf-demos/entrypoint.sh bg_sub -i $infile -b $bgfile -t ${params.cpus} --verbose
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
    /nrs/scicompsoft/kawaset/nf-demos/entrypoint.sh calc_stitch -i $infile --verbose
    """
}

process copy_stitching_parameters {
    container "janeliascicomp/n5-tools-py:1.1.0"
    containerOptions { getOptions([params.inputPath, params.outputPath, params.scriptPath]) }

    memory { "1 GB" }
    cpus { 1 }

    input:
    val src
    val tar
    val out

    output:
    val "${out}"
    
    script:
    """
    /nrs/scicompsoft/kawaset/nf-demos/entrypoint.sh copy_stitching_parameters -i $src -t $tar -o $out --verbose
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
    /nrs/scicompsoft/kawaset/nf-demos/entrypoint.sh copy_dims -i $src -t $tar --verbose
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
    nd2 = Channel.fromPath("${dir}/*.nd2")
    dist = nd2.map{ "${outdir}/${it.baseName}.xml" }
    n5xml = define_dataset(nd2, dist)
    n5xml.subscribe { println "n5xml: $it" }

    dist2 = nd2.map{ "${outdir}/${it.baseName}_fixed.xml" }
    fixedxml = fix_n5xml(n5xml, dist2)
    fixedxml.subscribe { println "fixedxml: $it" }

    subtracted = background_subtraction(bg, fixedxml)
    subtracted.subscribe { println "subtracted: $it" }

    base_dataset_name = file(baseimg).getBaseName()
    base = subtracted.filter{ file -> ["${base_dataset_name}"].find { file.contains(it) } }
    others = subtracted.filter{ file -> ["${base_dataset_name}"].find { !file.contains(it) } }

    calculated_base = calc_stitching(base)

    dist3 = base.map{ "${outdir}/${file(it).baseName}_fused_tmp.xml" }
    fused_base = fusion_base(calculated_base, dist3)

    dist4 = base.map{ "${outdir}/${file(it).baseName}_fused.xml" }
    resaved_base = resave_base(fused_base, dist4)

    src = calculated_base.first()
    dist5 = others.map{ "${outdir}/${file(it).baseName}_tmp.xml" }
    copied_others = copy_stitching_parameters(src, others, dist5)

    dist6 = others.map{ "${outdir}/${file(it).baseName}_fused_tmp.xml" }
    fused_others = fusion_others(copied_others, dist6)

    src2 = fused_base.first()
    copied_dims = copy_dims(src2, fused_others)

    dist7 = others.map{ "${outdir}/${file(it).baseName}_fused.xml" }
    resaved_others = resave_others(copied_dims, dist7)

    zeroToNine = Channel.from( 0..9 )
    chmap = nd2.map{ "${outdir}/${it.baseName}_fixed_fused.xml" }.merge(zeroToNine)
    resaved_base_with_ch = chmap.join(resaved_base)

    dist8 = base.map{ "${outdir}/export.n5" }
    final_n5_base = combine_n5_base(resaved_base_with_ch, dist8, "--attr")
    fix_res_base(base, final_n5_base, "--base")

    resaved_others_with_ch = chmap.join(resaved_others)
    dist9 = others.map{ "${outdir}/export.n5" }
    final_n5_others = combine_n5_others(resaved_others_with_ch, dist9, "")
    fix_res_others(others, final_n5_others, "")
}
