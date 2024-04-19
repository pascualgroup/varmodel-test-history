#!/bin/sh

# Uncomment this if you want to clone the code from scratch too
# ./clone-versions.sh

#./generate-sweep.jl before
#./generate-sweep-before.jl

./generate-sweep.jl after
#./generate-sweep-after.jl 

#./output/before/submit_jobs.sh
#./gather-output.jl output/before

./output/after/submit_jobs.sh
./gather-output.jl output/after

./compare.jl

