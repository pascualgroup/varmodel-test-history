#!/bin/sh

REPO="git@github.com:pascualgroup/varmodel3"

git clone $REPO varmodel3-before
cd varmodel3-before
git checkout a231dd080e57bb96a7bc54159f10a332c99ef8ec
cd ..

git clone $REPO varmodel3-after
cd varmodel3-after
git checkout 8bf65dfc443f05416091dd9fc3982c1f0b291b8e
