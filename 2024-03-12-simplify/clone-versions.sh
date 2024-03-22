#!/bin/sh

REPO="https://github.com/pascualgroup/varmodel3"

git clone $REPO varmodel3-before
cd varmodel3-before
git checkout fb4c106683631717c9fb06ee60d2a88593b57391
cd ..

git clone $REPO varmodel3-after
cd varmodel3-after
git checkout 2024-03-12-simplify
