



rule many_minimap:
    input:
        genome_folder=genome_folder,
        alignment_list="minimap/subsets/{subset}.txt",
        genome_stats= "tables/genome_stats.tsv"
    output:
        alignments_stats="minimap/alignments_stats/{subset}.tsv",
    log:
        "logs/minimap2/{subset}.txt"
    threads:
        config['threads']
    conda:
        "../envs/minimap2.yaml"
    params:
        minimap_extra= "-c --secondary=no -x asm10", #asm5/asm10/asm20: asm-to-ref mapping, for ~0.1/1/5% sequence divergence
        paf_folder="minimap/paf",
        extension='.fasta'
    script:
        "../scripts/many_minimap.py"



localrules: combine_paf
rule combine_paf:
    input:
        expand("minimap/alignments_stats/{subset}.tsv",
               subset=get_alignment_subsets(aligner='minimap'))
    output:
        "tables/minimap_dists.tsv"
    run:
        shell("head -n1 {input[0]} > {output}")
        for fin in input:
            shell("tail -n+2 {fin} >> {output}")

        in_dir= os.path.dirname(input[0])
        import shutil
        shutil.rmtree(in_dir)



## Mummer


def estimate_time_mummer(N,threads):
    "retur time in minutes"

    time_per_mummer_call = 1/60 # 1min in h

    return int(N*time_per_mummer_call)//threads + 5



rule run_mummer:
    input:
        comparison_list="mummer/subsets/{subset}.txt",
        genome_folder= genome_folder,
        genome_stats="tables/genome_stats.tsv",
    output:
        temp("mummer/ANI/{subset}.tsv")
    threads:
        config['threads']
    conda:
        "../envs/mummer.yaml"
    resources:
        time= lambda wc, input, threads: estimate_time_mummer(config['mummer']['subset_size'],threads),
        mem= config['mummer'].get('mem',5)
    log:
        "logs/mummer/workflows/{subset}.txt"
    params:
        path= os.path.dirname(workflow.snakefile)
    shell:
        "snakemake -s {params.path}/rules/mummer.smk "
        "--config comparison_list='{input.comparison_list}' "
        " genome_folder='{input.genome_folder}' "
        " subset={wildcards.subset} "
        " genome_stats={input.genome_stats} "
        " --rerun-incomplete "
        "-j {threads} --nolock 2> {log}"



def get_merge_mummer_ani_input(wildcards):

    subsets=get_mummer_subsets(aligner="mummer")

    return expand("mummer/ANI/{subset}.tsv",subset=subsets)

localrules: merge_mummer_ani
rule merge_mummer_ani:
    input:
        get_merge_mummer_ani_input
    output:
        "tables/mummer_dists.tsv"
    run:
        import pandas as pd
        import shutil

        Mummer={}
        for file in input:
            Mummer[io.simplify_path(file)]= pd.read_csv(file,index_col=[0,1],sep='\t')

        M= pd.concat(Mummer,axis=0)
        M.index= M.index.droplevel(0)
        M.to_csv(output[0],sep='\t')


        ani_dir= os.path.dirname(input[0])
        shutil.rmtree(ani_dir)
        #sns.jointplot('ANI','Coverage',data=M.query('ANI>0.98'),kind='hex',gridsize=100,vmax=200)