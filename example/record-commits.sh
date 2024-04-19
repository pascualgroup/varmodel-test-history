#!/bin/sh

cd varmodel3-before
git rev-parse HEAD > ../commit-before.txt
cd ..

cd varmodel3-after
git rev-parse HEAD > ../commit-after.txt
