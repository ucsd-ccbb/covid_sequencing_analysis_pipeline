#!/bin/bash

PIPELINEDIR=/shared/workspace/software/covid_sequencing_analysis_pipeline

cd $PIPELINEDIR && \
echo $(git describe --tags) && echo $(git log | head -n 1) && echo $(git checkout)
