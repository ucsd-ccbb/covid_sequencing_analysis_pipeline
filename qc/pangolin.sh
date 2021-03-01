#!/bin/bash

export PATH=/shared/workspace/software/pangolin:$PATH
# Activate conda env covid1.2
ANACONDADIR=/shared/workspace/software/anaconda3/bin
source $ANACONDADIR/activate pangolin

PREFIX=$1 # $WORKSPACE/$SEQ_RUN

# filter the true samples
awk '{ if ($2 == "True") { print } }' "$PREFIX"-summary.acceptance.tsv > "$PREFIX"-summary.acceptance.true.tsv
awk '{print $1}' "$PREFIX"-summary.acceptance.true.tsv > "$PREFIX"-passQC.samples.tsv

# loop over individual .fa files, keep the ones which are in passQC.samples.tsv
touch "$PREFIX"-passQC.fas # initialize the file
for f in *.fa; do 
    fshort="$(cut -d'.' -f1 <<<$f)"
    echo $fshort
    
    if (grep -qF $fshort "$PREFIX"-passQC.samples.tsv); then
       #echo "Found it"
       cat $f >> "$PREFIX"-passQC.fas
    fi

done


# note: should always update pangolin to get the most recent variant classifications... but this updates code as well as data... may be problematic
# pangolin --update
pangolin -t 32 --outfile "$PREFIX".lineage_report.csv "$PREFIX"-passQC.fas
