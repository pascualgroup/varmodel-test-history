#!/bin/sh

REPO="git@github.com:pascualgroup/varmodel3"

git clone $REPO varmodel3-before
cd varmodel3-before
git checkout `cat ../commit-before.txt`
cd ..

git clone $REPO varmodel3-after
cd varmodel3-after
git checkout `cat ../commit-after.txt`

