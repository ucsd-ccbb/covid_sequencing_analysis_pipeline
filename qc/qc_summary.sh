#!/bin/bash

export PATH=/shared/workspace/software/anaconda3/envs/covid1.1/bin:$PATH

PIPELINEDIR=/shared/workspace/software/covid_sequencing_analysis_pipeline
mkdir -p $WORKSPACE/qc


runQC () {

	aws s3 cp $S3DOWNLOAD/ $WORKSPACE/ \
		--quiet \
		--recursive \
		--exclude "*" \
		--include "*.variants.tsv" \
		--include "*.consensus.fa" \
		--include "*.depth.txt" \
		--include "*fastqc.zip" \
		--include "*.sorted.stats" \
		--include "*.acceptance.tsv"

	mv $WORKSPACE/*/*.variants.tsv $WORKSPACE/*/*.consensus.fa $WORKSPACE/*/*.depth.txt $WORKSPACE/*/*.acceptance.tsv $WORKSPACE
	cat $WORKSPACE/*.consensus.fa > $WORKSPACE/consensus.fas
	cd $WORKSPACE && zip -9 variants.zip *.variants.tsv && zip -9 consensus.zip *.consensus.fa && zip -9 depth.zip *.depth.txt

	# summary figures and stats
	echo "Generating a violin plot of mapping depth across all samples."
	python $PIPELINEDIR/qc/samtools_depth_violinplot.py $WORKSPACE/*.depth.txt && mv depth_violin.pdf $WORKSPACE/qc
	echo "Generating line plots of mapping depth across all samples."
	python $PIPELINEDIR/qc/samtools_depth_lineplot.py $WORKSPACE/*.depth.txt && mv depth_lineplot.pdf $WORKSPACE/qc
	echo "Concatenating samtools depth output across all samples into a single TSV."
	python $PIPELINEDIR/qc/samtools_depth_concat.py $WORKSPACE/*.depth.txt > $WORKSPACE/qc/depth.tsv
	echo "Listing the positions with a depth below 10 reads."
	python $PIPELINEDIR/qc/samtools_depth_low.py 266 29674 10 $WORKSPACE/*.depth.txt > $WORKSPACE/qc/depth_below_10.tsv
	echo "Summarizing consensus QC."
	python $PIPELINEDIR/qc/consensus_acceptance_summary.py 
	# Multiqc
	multiqc --config $PIPELINEDIR/qc/covid_custom_config.yaml $WORKSPACE

	echo "Uploading QC results."
	aws s3 cp $WORKSPACE/variants.zip $S3DOWNLOAD/ --quiet
	aws s3 cp $WORKSPACE/consensus.zip $S3DOWNLOAD/ --quiet
	aws s3 cp $WORKSPACE/consensus.fas $S3DOWNLOAD/ --quiet
	aws s3 cp $WORKSPACE/depth.zip $S3DOWNLOAD/ --quiet
	aws s3 cp $WORKSPACE/multiqc_data/ $S3DOWNLOAD/qc/multiqc_data/ -quiet --recursive
	aws s3 cp $WORKSPACE/multiqc_report.html $S3DOWNLOAD/qc/
	aws s3 cp $WORKSPACE/qc/ $S3DOWNLOAD/qc/ --quiet --recursive
	aws s3 cp $WORKSPACE/summary.acceptance.tsv $S3DOWNLOAD/qc/ --quiet

}

{ time ( runQC ) ; } > $WORKSPACE/qc/qc_summary.log 2>&1

