__author__ = "Johannes Alneberg"
__license__ = "MIT"


import os
import sys
import shutil
import glob
from subprocess import check_output
from collections import defaultdict

# Check that no submodule git repo is dirty
submodules = ["snakemake-workflows", "toolbox"]
for submodule in submodules:
    submodule_status = check_output(["git", "status", "--porcelain", submodule])
    if not submodule_status == b"":
        print(submodule_status)
        raise Exception("Submodule {} is dirty. Commit changes before proceeding.".format(submodule))

# Check that the git repo is not dirty
submodule_status = check_output(["git", "status", "--porcelain"])
if not submodule_status == b"":
    print(submodule_status)
    raise Exception("Repo is dirty. Commit changes before proceeding.")

# Chose config file based on if we're on uppmax or not
if 'SNIC_RESOURCE' in os.environ:
    configfile: "config_uppmax.json"
else:
    configfile: "config.json"

config["fastqc_rules"]["reads"] = {}
config["cutadapt_rules"]["reads"] = {}
config["megahit_rules"]["samples"] = {}

with open("sample_indices.json") as si:
    sample_indices = json.load(si)
def default_analysis():
    return "quality_adapter_no_indices"

analysis_per_sample = defaultdict(default_analysis)
with open("analysis_per_sample.json") as aps:
    analysis_per_sample.update(json.load(aps))

with open("sample_groups.json") as sg:
    sample_groups = json.load(sg)

for read_file in glob.glob("samples/raw/dna/*.fq.gz"):
    read_basename = os.path.basename(read_file)
    read_mate_name = read_basename.replace(".fq.gz", "")
    config["fastqc_rules"]["reads"][read_mate_name] = read_file
   
    read_name = read_mate_name.replace("_R1", "").replace("_R2", "")
    
    # Add all steps to fastqc - this will cause fastqc to run after each step 
    # as well as on the raw reads 
    for trim_params_name, trim_params_dict in config["cutadapt_rules"]["trim_params"].items():
        if trim_params_name not in analysis_per_sample[read_name]:
            continue

        config["fastqc_rules"]["reads"]["cutadapt_"+trim_params_name+"_"+read_mate_name] = \
            "cutadapt/adapt_cutting/{trim_params}/{read}".format(
                trim_params=trim_params_name,
                read = read_basename
            ) 

        config["fastqc_rules"]["reads"]["fastuniq_"+trim_params_name+"_"+read_mate_name] = \
            "fastuniq/{trim_params}/{read}".format(
                trim_params=trim_params_name,
                read = read_basename
            ) 

    # Hack to get read pairs in a list
    if read_name in config["cutadapt_rules"]["reads"]:
        config["cutadapt_rules"]["reads"][read_name].append(read_file)
        config["cutadapt_rules"]["reads"][read_name].sort()
    else:
        config["cutadapt_rules"]["reads"][read_name] = [read_file]
    
    # Add the variable barcode sequences for each sample to cutadapt config
    trim_params_names = analysis_per_sample[read_name]
    for trim_params_name, trim_params_config in config["cutadapt_rules"]["trim_params"].items():
        if trim_params_name in trim_params_names:
            if "common_variables" in trim_params_config.keys():
                variables = config["cutadapt_rules"]["trim_params"][trim_params_name]["common_variables"].copy()
                if read_name in sample_indices["R1_index"]:
                    variables["R1_index"] = sample_indices["R1_index"][read_name]
                    variables["R2_rev_index"] = sample_indices["R2_rev_index"][read_name]
                if "variables" not in config["cutadapt_rules"]["trim_params"][trim_params_name]:
                    config["cutadapt_rules"]["trim_params"][trim_params_name]["variables"] = {}
                config["cutadapt_rules"]["trim_params"][trim_params_name]["variables"][read_name] = variables


for read_file in glob.glob("samples/raw/rna/*.fq.gz"):
    read_basename = os.path.basename(read_file)
    read_mate_name = read_basename.replace(".fq.gz", "")
    config["fastqc_rules"]["reads"][read_mate_name] = read_file
   
    read_name = read_mate_name.replace("_R1", "").replace("_R2", "")
    
    # Add all steps to fastqc - this will cause fastqc to run after each step 
    # as well as on the raw reads 
    for trim_params_name, trim_params_dict in config["cutadapt_rules"]["trim_params"].items():
        if trim_params_name not in analysis_per_sample[read_name]:
            continue

        config["fastqc_rules"]["reads"]["cutadapt_"+trim_params_name+"_"+read_mate_name] = \
            "cutadapt/adapt_cutting/{trim_params}/{read}".format(
                trim_params=trim_params_name,
                read = read_basename
            ) 

    # Hack to get read pairs in a list
    if read_name in config["cutadapt_rules"]["reads"]:
        config["cutadapt_rules"]["reads"][read_name].append(read_file)
        config["cutadapt_rules"]["reads"][read_name].sort()
    else:
        config["cutadapt_rules"]["reads"][read_name] = [read_file]
    
    # Add the variable barcode sequences for each sample to cutadapt config
    trim_params_names = analysis_per_sample[read_name]
    for trim_params_name, trim_params_config in config["cutadapt_rules"]["trim_params"].items():
        if trim_params_name in trim_params_names:
            if "common_variables" in trim_params_config.keys():
                variables = config["cutadapt_rules"]["trim_params"][trim_params_name]["common_variables"].copy()
                if read_name in sample_indices["R1_index"]:
                    variables["R1_index"] = sample_indices["R1_index"][read_name]
                    variables["R2_rev_index"] = sample_indices["R2_rev_index"][read_name]
                if "variables" not in config["cutadapt_rules"]["trim_params"][trim_params_name]:
                    config["cutadapt_rules"]["trim_params"][trim_params_name]["variables"] = {}
                config["cutadapt_rules"]["trim_params"][trim_params_name]["variables"][read_name] = variables

config["bowtie2_rules"]["references"] = {}
config["bowtie2_rules"]["units"] = {}
config["bowtie2_rules"]["samples"] = {}

# Add reads that will go through internal standards protocol before added to the pipeline
for read_file in glob.glob("only_for_mapping/with_internal_standards/dna/*.fq.gz"):
    read_basename = os.path.basename(read_file)
    read_name = read_basename.replace(".fq.gz", "")
    sample_name = read_name.replace("_R1", "").replace("_R2", "")
    
    # Adding to bowtie2_rules instead of bowtie2_quant_rules
    # So that the mapping against the reference genome can 
    # work without adding the samples to the pipeline 
    if sample_name in config["bowtie2_quant_rules"]["samples"]:
        config["internal_standards"]["samples"].append(sample_name)
        config["bowtie2_rules"]["units"][sample_name].append(read_file)
        config["bowtie2_rules"]["units"][sample_name].sort()
    else:
        config["bowtie2_rules"]["units"][sample_name] = [read_file]
        config["bowtie2_rules"]["samples"][sample_name] = [sample_name]

# Load information on which internal standard have been used
with open("internal_standards.json") as i_s:
    internal_standards = json.load(i_s)

config["internal_standards"]["sample_to_reference"] = {}

for sample, reference in internal_standards.items():
    ref_name = reference.split('/')[-2]
    if ref_name not in config["bowtie2_rules"]["references"]:
        config["bowtie2_rules"]["references"][ref_name] = reference

    config["internal_standards"]["sample_to_reference"][sample] = ref_name

config["taxonomic_annotation"]["sample_sets"] = config['bowtie2_quant_rules']["split_ref_sets"]


WORKFLOW_DIR = "snakemake-workflows/"

include: os.path.join(WORKFLOW_DIR, "bio/ngs/rules/mapping/samtools.rules")
include: os.path.join(WORKFLOW_DIR, "bio/ngs/rules/blast/rpsblast.rules")
#include: os.path.join(WORKFLOW_DIR, "rules/quantification/rpkm.rules")
include: os.path.join(WORKFLOW_DIR, "bio/ngs/rules/trimming/cutadapt.rules")
include: os.path.join(WORKFLOW_DIR, "bio/ngs/rules/quality_control/fastqc.rules")
include: os.path.join(WORKFLOW_DIR, "bio/ngs/rules/duplicate_removal/fastuniq.rules")
include: os.path.join(WORKFLOW_DIR, "bio/ngs/rules/assembly/megahit.rules")
include: os.path.join(WORKFLOW_DIR, "bio/ngs/rules/taxonomic_annotation/megan.rules")
include: os.path.join(WORKFLOW_DIR, "bio/ngs/rules/quality_control/internal_standards.rules")

## Enable this when internal_standards mapping is done
#ruleorder: bowtie2_map > bowtie2_map_large

rule preprocess_all:
    input:
        htmls=expand("fastqc/{reads}/{reads}_fastqc.html", reads=config["fastqc_rules"]["reads"]),
        zips=expand("fastqc/{reads}/{reads}_fastqc.zip", reads=config["fastqc_rules"]["reads"])

rule quantify_all:
    input:
        expand("quantification/{assembly}/orf/{samples}/{samples}.rpkm",
            samples = ["P1414_101", "P1414_102", "P1414_103"],
            assembly = "assembly_v1"),


# Testing rules and configs
rule cutadapt_all_test:
    """Trim all reads with all supplied trimming parameters"""
    input:
        trimmed_reads=expand("cutadapt/adapt_cutting/{trim_params}/{reads}_{ext}.fq.gz",
        reads={"120628": ['samples/raw/120628_R1.fq.gz', 'samples/raw/120628_R2.fq.gz']},
        trim_params=config["cutadapt_rules"]["trim_params"],
        ext=["R1","R2"])

test_reads_orig = {
            "P1994_101_R1": "samples/raw/P1994_101_R1.fq.gz",
            "P1994_101_R2": "samples/raw/P1994_101_R2.fq.gz",
            "P1994_102_R1": "samples/raw/P1994_102_R1.fq.gz",
            "P1994_102_R2": "samples/raw/P1994_102_R2.fq.gz",
            "P1994_110_R1": "samples/raw/P1994_110_R1.fq.gz",
            "P1994_110_R2": "samples/raw/P1994_110_R2.fq.gz"
        }

test_reads = {}
for read_name, read_file in test_reads_orig.items():
    test_reads[read_name] = read_file
    read_basename = os.path.basename(read_file)
    for trim_params_name, trim_params_dict in config["cutadapt_rules"]["trim_params"].items():
        test_reads["cutadapt_" + trim_params_name + "_" + read_name] = \ 
            "cutadapt/adapt_cutting/{trim_params}/{read}".format(
                trim_params=trim_params_name,
                read = read_basename
            )

        test_reads["fastuniq_"+trim_params_name+"_"+read_name] = \
            "fastuniq/{trim_params}/{read}".format(
                trim_params=trim_params_name,
                read = read_basename
            ) 

rule fastqc_all_test:
    input:
        htmls=expand("fastqc/{reads}/{reads}_fastqc.html", reads=test_reads),
        zips=expand("fastqc/{reads}/{reads}_fastqc.zip", reads=test_reads)

