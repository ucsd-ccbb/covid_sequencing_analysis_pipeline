#!/bin/bash

INPUT=$1 # Sample Sheet with header - organization,seqrun,primers,reads,merge,variants,qc,lineage,tree_build,read_cap,istest
PIPELINEDIR=/shared/workspace/software/covid_sequencing_analysis_pipeline
S3HELIX=s3://helix-all
S3UCSD=s3://ucsd-all
QSUBSAMPLEPARAMS=''
ANACONDADIR=/shared/workspace/software/anaconda3/bin
source $ANACONDADIR/activate covid1.2

[ ! -f $INPUT ] && { echo "Error: $INPUT file not found"; exit 99; }
sed 1d $INPUT | while IFS=',' read ORGANIZATION SEQ_RUN PRIMER_SET FQ MERGE_LANES VARIANTS QC LINEAGE TREE_BUILD READ_CAP ISTEST
do
	TIMESTAMP=$(date +'%Y-%m-%d_%H-%M-%S')
	sleep 1

	if [[ ! "$ORGANIZATION" =~ ^(ucsd|helix)$ ]]; then
		echo "Error: Parameter ORGANIZATION must be one of ucsd or helix"
		exit 1
	fi

	if [[ "$ORGANIZATION" == ucsd ]]; then
		S3DOWNLOAD=$S3UCSD
	elif [[ "$ORGANIZATION" == helix ]]; then
		S3DOWNLOAD=$S3HELIX
	fi
	FASTQS_PATH=$S3DOWNLOAD/$SEQ_RUN/"$SEQ_RUN"_fastq

	if [[ ! "$PRIMER_SET" =~ ^(artic|swift_v2)$ ]]; then
		echo "Error: Parameter PRIMER_SET must be one of artic or swift_v2"
		exit 1
	fi

	if [[ ! "$FQ" =~ ^(se|pe)$ ]]; then
	  echo "Error: FQ must be one of se or pe"
	  exit 1
	fi

	if [[ ! "$MERGE_LANES" =~ ^(true|false)$ ]]; then
	  echo "Error: MERGE_LANES must be one of true or false"
	  exit 1
	fi

	if [[ ! "$VARIANTS" =~ ^(true|false)$ ]]; then
	  echo "Error: VARIANTS must be one of true or false"
	  exit 1
	fi

	if [[ ! "$QC" =~ ^(true|false)$ ]]; then
	  echo "Error: QC must be one of true or false"
	  exit 1
	fi

	if [[ ! "$LINEAGE" =~ ^(true|false)$ ]]; then
	  echo "Error: LINEAGE must be one of true or false"
	  exit 1
	fi

	if [[ ! "$TREE_BUILD" =~ ^(true|false)$ ]]; then
	  echo "Error: TREE_BUILD must be one of true or false"
	  exit 1
	fi

	re='^[0-9]+$'
	if [[ ! $READ_CAP =~ ^($re|all)$ ]] ; then
	   echo "Error: READ_CAP must be an integer or 'all'"
	   #exit 1
	fi

	echo "Organization: $ORGANIZATION"
	echo "Seq_Run: $SEQ_RUN"
	echo "Timestamp: $TIMESTAMP"
	echo "S3 Fastq path: $FASTQS_PATH"
	echo "Primers: $PRIMER_SET"
	echo "Fastq Reads: $FQ"
	echo "Merge Lanes: $MERGE_LANES"
	echo "Extract $READ_CAP mapped reads"
	echo "Call Variants: $VARIANTS"
	echo "Run QC: $QC"
	echo "Lineage with Pangolin: $LINEAGE"
	echo "Run tree building: $TREE_BUILD"
	echo "Is test run: $ISTEST"

  # TODO: move this out of this script? Should be an optional pre-step that we rarely need
	# add_seq_run_to_fastq_name.py
	# echo "Checking fastq names for seq_run."
	# python $PIPELINEDIR/pipeline/add_seq_run_to_fastq_name.py $SEQ_RUN $FASTQS_PATH/ > $SEQ_RUN.fastq_rename.log 2>&1
	
	DELIMITER=_R1_001.fastq.gz
  	BOTH_FASTQS=$(aws s3 ls $FASTQS_PATH/ |  grep ".fastq.gz" | sort -k3 -n | awk '{print $NF}' | sort | uniq | grep -v Undetermined)
	R1_FASTQS=$(echo "$BOTH_FASTQS" |  grep $DELIMITER )

	# Merge fastq files from multiple lanes
	if [[ "$MERGE_LANES" == true ]]; then
	  # get the (non-unique) list of sample identifiers without lane/read info (but with sample number)
    INSPECT_DELIMITER=__
    SAMPLES_WO_LANES_LIST=()
    for R1_FASTQ in $(echo $R1_FASTQS); do
      SEQUENCING_INFO=$(echo $R1_FASTQ | awk -F $INSPECT_DELIMITER '{print $NF}')
      SAMPLE_NUM=$(echo $SEQUENCING_INFO | awk -F _ '{print $1}')
      A_SAMPLE=$(echo $R1_FASTQ | sed "s/$SEQUENCING_INFO/$SAMPLE_NUM/g")
      SAMPLES_WO_LANES_LIST+=($A_SAMPLE)
    done

    # reduce above list to only unique values and loop over them
    FINAL_R1_FASTQS=()
    for SAMPLE in $(printf '%s\n' "${SAMPLES_WO_LANES_LIST[@]}" | sort | uniq ); do
      LANES=$(echo "$BOTH_FASTQS" | grep "$SAMPLE" | awk -F $INSPECT_DELIMITER '{print $NF}'| awk -F '_L|_R' '{print $2}' | sort | uniq | grep 00)
      LANES_COMBINED=$(echo $LANES | sed 's/ //g')

      FINAL_R1_FASTQS+=("$SAMPLE"_"$LANES_COMBINED""$DELIMITER")
    done

		qsub -v SEQ_RUN=$SEQ_RUN \
			 -v WORKSPACE=/scratch/$SEQ_RUN/$TIMESTAMP \
			 -v S3DOWNLOAD=$S3DOWNLOAD/$SEQ_RUN/"$SEQ_RUN"_fastq \
			 -wd /shared/workspace/projects/covid/logs \
			 -N merge_fq_lanes_"$SEQ_RUN" \
			 -pe smp 16 \
			 -S /bin/bash \
			 $PIPELINEDIR/pipeline/merge_lanes.sh

		R1_FASTQS=$(printf '%s\n' "${FINAL_R1_FASTQS[@]}")
		QSUBSAMPLEPARAMS=' -hold_jid merge_fq_lanes_'$SEQ_RUN''
	fi

	SAMPLE_LIST=$(echo "$R1_FASTQS" | awk -F $DELIMITER '{print $1}' | sort | uniq)
	if [[ "$SAMPLE_LIST" == "" ]]; then
		echo "Error: There are no samples to run in $FASTQS_PATH"
		exit 1
	fi

	if [[ "$VARIANTS" == true ]]; then

		# Run pipeline on each sample
		for SAMPLE in $SAMPLE_LIST; do
			qsub $QSUBSAMPLEPARAMS \
				-v SEQ_RUN="$SEQ_RUN" \
				-v SAMPLE=$SAMPLE \
				-v S3DOWNLOAD=$S3DOWNLOAD \
				-v PRIMER_SET=$PRIMER_SET \
				-v MERGE_LANES=$MERGE_LANES \
				-v FQ=$FQ \
				-v TIMESTAMP=$TIMESTAMP \
				-v READ_CAP=$READ_CAP \
				-N Covid19_"$SEQ_RUN"_"$TIMESTAMP"_"$SAMPLE" \
				-wd /shared/workspace/projects/covid/logs \
				-pe smp 2 \
				-S /bin/bash \
				$PIPELINEDIR/pipeline/sarscov2_consensus_pipeline.sh
		done
	fi

	if [[ "$QC" == true ]]; then
			qsub \
				-hold_jid 'Covid19_'$SEQ_RUN'_'$TIMESTAMP'_*' \
				-v SEQ_RUN=$SEQ_RUN \
				-v S3DOWNLOAD=$S3DOWNLOAD \
				-v WORKSPACE=/scratch/$SEQ_RUN/$TIMESTAMP \
				-v FQ=$FQ \
				-v TIMESTAMP=$TIMESTAMP \
				-v ISTEST=$ISTEST \
				-N QC_summary_"$SEQ_RUN" \
				-wd /shared/workspace/projects/covid/logs \
				-pe smp 32 \
				-S /bin/bash \
		    	$PIPELINEDIR/qc/qc_summary.sh
	fi

    # Tree building
    if [[ "$LINEAGE" == true ]]; then
	    qsub \
			-hold_jid 'QC_summary_'$SEQ_RUN'' \
			-v ORGANIZATION=$ORGANIZATION \
			-v TREE_BUILD=$TREE_BUILD \
			-v TIMESTAMP=$TIMESTAMP \
			-v ISTEST=$ISTEST \
			-v WORKSPACE=/scratch/phylogeny/$TIMESTAMP \
			-N tree_building \
			-wd /shared/workspace/projects/covid/logs \
			-pe smp 96 \
			-S /bin/bash \
	    	$PIPELINEDIR/pipeline/phylogeny.sh

    fi

	echo "organization,seq_run,primers,reads,merge,variants,qc,lineage,tree_build,read_cap,is_test" > "$SEQ_RUN"-"$TIMESTAMP".csv
	echo "$ORGANIZATION,$SEQ_RUN,$PRIMER_SET,$FQ,$MERGE_LANES,$VARIANTS,$QC,$LINEAGE,$TREE_BUILD,$READ_CAP,$ISTEST" >> "$SEQ_RUN"-"$TIMESTAMP".csv

	bash $PIPELINEDIR/pipeline/show_version.sh >> "$SEQ_RUN"-"$TIMESTAMP".version.log

	aws s3 cp "$SEQ_RUN"-"$TIMESTAMP".csv $S3DOWNLOAD/$SEQ_RUN/"$SEQ_RUN"_results/"$TIMESTAMP"_"$FQ"/"$SEQ_RUN"_summary_files/
	aws s3 cp "$SEQ_RUN"-"$TIMESTAMP".version.log $S3DOWNLOAD/$SEQ_RUN/"$SEQ_RUN"_results/"$TIMESTAMP"_"$FQ"/"$SEQ_RUN"_summary_files/
	# aws s3 cp $SEQ_RUN.fastq_rename.log $S3DOWNLOAD/$SEQ_RUN/"$SEQ_RUN"_results/"$TIMESTAMP"_"$FQ"/"$SEQ_RUN"_summary_files/

	rm "$SEQ_RUN"-"$TIMESTAMP".csv
	rm "$SEQ_RUN"-"$TIMESTAMP".version.log
	# rm $SEQ_RUN.fastq_rename.log
done
