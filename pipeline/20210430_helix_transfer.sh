# Transfer HELIX based on run name
# METADATA=$1 #20210429_ccbb_full_metadata.csv
SEQ_RUN=$1 #210314_A00953_0254_BHYGTMDSXY
S3UCSD=s3://ucsd-all/$SEQ_RUN
S3HELIX=s3://helix-research-ngs-results/UCSD
TIMESTAMP=$(aws s3 ls $S3UCSD/"$SEQ_RUN"_results/ | tail -n 1 | awk -F 'PRE \|/' '{print $2}')
WORKSPACE=/shared/transfer/$TIMESTAMP
mkdir -p transfer

# SAMPLES=$(awk -F ',' '{ if ($50 == HELIX) { print $1} }' $METADATA)
# for SAMPLE in $SAMPLES; do
# 	aws s3 cp \
# 	$S3UCSD/"$SEQ_RUN"_results/$TIMESTAMP/"$SEQ_RUN"_samples/$SAMPLE/ \ $S3HELIX/"$SEQ_RUN"_results/$TIMESTAMP/"$SEQ_RUN"_samples/$SAMPLE/ \
# 	--recursive --acl bucket-owner-full-control
# done

# # aws s3 cp $S3UCSD/"$SEQ_RUN"_results/$TIMESTAMP/"$SEQ_RUN"_summary_files/ $WORKSPACE/ \
# # 	--recursive \
# # 	--exclude "*" \
# # 	--include "*summary.csv" \
# # 	--include "*coverage.tsv" \
# # 	--include "*acceptance.tsv" \
# # 	--include "*summary.csv" \
# # 	--include "*fas"

aws s3 cp $S3UCSD/"$SEQ_RUN"_results/$TIMESTAMP/"$SEQ_RUN"_summary_files/ $WORKSPACE/ \
	--recursive \
	--exclude "*" \
	--include "*consensus.zip"

aws s3 cp $S3UCSD/"$SEQ_RUN"_fastq/ $WORKSPACE/ \
	--recursive \
	--exclude "*" \
	--include "*.fastq.gz"

aws s3 cp $WORKSPACE $S3HELIX/$SEQ_RUN/ --recursive --acl bucket-owner-full-control

rm -r $WORKSPACE

# head -n 1 $WORKSPACE/"$SEQ_RUN"-summary.csv > $WORKSPACE/"$SEQ_RUN"-helix-summary.csv
# fgrep "$SAMPLES" $WORKSPACE/"$SEQ_RUN"-summary.csv >> $WORKSPACE/"$SEQ_RUN"-helix-summary.csv
# aws s3 cp $WORKSPACE/"$SEQ_RUN"-helix-summary.csv $S3HELIX/"$SEQ_RUN"_results/$TIMESTAMP/"$SEQ_RUN"_summary_files/
