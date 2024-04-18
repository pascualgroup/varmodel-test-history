#!/bin/sh

REPO="git@github.com:pascualgroup/varmodel3"

git clone $REPO varmodel3-before
cd varmodel3-before
git checkout a231dd080e57bb96a7bc54159f10a332c99ef8ec
cd ..

git clone $REPO varmodel3-after
cd varmodel3-after
git checkout 6b83ab597845bb53a7b5ea20093b229135e8aaa5

