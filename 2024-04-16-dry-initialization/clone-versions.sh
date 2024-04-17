#!/bin/sh

REPO="git@github.com:pascualgroup/varmodel3"

git clone $REPO varmodel3-before
cd varmodel3-before
git checkout 03a83e521847574f459ac5d15d6ea242c6093fa8
cd ..

git clone $REPO varmodel3-after
cd varmodel3-after
git checkout a231dd080e57bb96a7bc54159f10a332c99ef8ec

