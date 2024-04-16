#!/bin/sh

REPO="git@github.com:pascualgroup/varmodel3"

git clone $REPO varmodel3-before
cd varmodel3-before
git checkout a46a220e6d5d02002d93677849e965043a8b8514
cd ..

git clone $REPO varmodel3-after
cd varmodel3-after
git checkout 68cdd135d8cf2c59485c9920f32d06dce7083430

