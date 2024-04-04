#!/bin/sh

REPO="https://github.com/pascualgroup/varmodel3"

git clone $REPO varmodel3-before
cd varmodel3-before
git checkout 2024-04-01-optimize-before
cd ..

git clone $REPO varmodel3-after
cd varmodel3-after
git checkout 2024-04-01-optimize-after
