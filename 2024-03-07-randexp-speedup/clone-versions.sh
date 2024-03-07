#!/bin/sh

REPO="https://github.com/pascualgroup/varmodel3"

git clone $REPO varmodel3-before
cd varmodel3-before
git checkout ae182d0
cd ..

git clone $REPO varmodel3-after
cd varmodel3-after
git checkout 2024-03-07-randexp-speedup
