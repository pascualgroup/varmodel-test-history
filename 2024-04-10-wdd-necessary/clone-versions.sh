#!/bin/sh

REPO="git@github.com:pascualgroup/varmodel3"

git clone $REPO varmodel3-before
cd varmodel3-before
git checkout 2024-04-10-wdd-necessary-before
cd ..

git clone $REPO varmodel3-after
cd varmodel3-after
git checkout 2024-04-10-wdd-necessary-after
