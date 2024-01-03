
include { getOptions } from '../utils' 

process fusion {
    container "janeliascicomp/n5-tools-py:1.1.0"
    containerOptions { getOptions([params.inputPath, params.outputPath, params.scriptPath]) }

    memory { "${params.mem_gb} GB" }
    cpus { params.cpus }

    input:
    tuple val(infile), val(outfile)

    output:
    val "${outfile}"
    
    script:
    """
    echo /nrs/scicompsoft/kawaset/nf-demos/entrypoint.sh fuse -i $infile -o $outfile
    """
}

process fusion_spark {
    container "janeliascicomp/n5-tools-py:1.1.0"
    containerOptions { getOptions([params.inputPath, params.outputPath, params.scriptPath]) }

    memory { "${params.mem_gb} GB" }
    cpus { params.cpus }

    input:
    tuple val(infile), val(outfile)

    output:
    val "${outfile}"
    
    script:
    """
    export JAVA_HOME="/misc/sc/jdks/zulu11.56.19-ca-jdk11.0.15-linux_x64"
    java -Xmx600g -Dspark.master=local[48] /nrs/scicompsoft/kawaset/Liu3/tktest/BigStitcher-Spark-0.0.2-SNAPSHOT.jar net.preibisch.bigstitcher.spark.AffineFusion ""
    """
}

process resave_t {
    container "janeliascicomp/n5-tools-py:1.1.0"
    containerOptions { getOptions([params.inputPath, params.outputPath, params.scriptPath]) }

    memory { "600 GB" }
    cpus { 48 }

    input:
    val infile
    tuple val(outfile), val(outdir), val(time)

    output:
    val "${outfile}"
    
    script:
    """
    echo /groups/scicompsoft/home/kawaset/BigStitcher-Spark/resave-n5 -x $infile -xo $outfile -o $outdir -t $time --blockSize 512,512,64 -ds 1,1,1 > /dev/null 2>&1
    """
}

process resave {
    container "janeliascicomp/n5-tools-py:1.1.0"
    containerOptions { getOptions([params.inputPath, params.outputPath, params.scriptPath]) }

    memory { "600 GB" }
    cpus { 48 }

    input:
    tuple val(infile), val(outfile)
    val(control_1) 

    output:
    val "${outfile}"
    
    script:
    """
    echo /nrs/scicompsoft/kawaset/nf-demos/entrypoint.sh resave -i $infile -o $outfile -t ${params.cpus} > /dev/null 2>&1
    """
}

process combine_n5 {
    container "janeliascicomp/n5-tools-py:1.1.0"
    containerOptions { getOptions([params.inputPath, params.outputPath, params.scriptPath]) }

    memory { "${params.mem_gb} GB" }
    cpus { params.cpus }
    
    input:
    tuple val(src), val(ch)
    val dst
    val options

    output:
    tuple val("${dst}"), val(ch)
    
    script:
    """
    echo /nrs/scicompsoft/kawaset/nf-demos/entrypoint.sh combine_n5 -i $src -o $dst -c $ch $options
    """

}

process fix_res {
    container "janeliascicomp/n5-tools-py:1.1.0"
    containerOptions { getOptions([params.inputPath, params.outputPath, params.scriptPath]) }

    memory { "4 GB" }
    cpus { 1 }

    input:
    tuple val(src), val(dst)

    output:
    val "${dst}"
    
    script:
    """
    echo /nrs/scicompsoft/kawaset/nf-demos/entrypoint.sh fix_res -i $src -o $dst
    """
}
