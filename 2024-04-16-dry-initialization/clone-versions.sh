#!/bin/sh

REPO="git@github.com:pascualgroup/varmodel3"

git clone $REPO varmodel3-before
cd varmodel3-before
git checkout 03a83e521847574f459ac5d15d6ea242c6093fa8
cd ..

git clone $REPO varmodel3-after
cd varmodel3-after
git checkout 09f208790019b394863c1be7eeb79e922aab4ad6
