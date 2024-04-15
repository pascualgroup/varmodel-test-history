#!/bin/sh

REPO="git@github.com:pascualgroup/varmodel3"

git clone $REPO varmodel3-before
cd varmodel3-before
git checkout fb53c29d2f008c6638ffc4e190b90163549ec67f
cd ..

git clone $REPO varmodel3-after
cd varmodel3-after
git checkout 98115925ca34e6d546413fae996eb9d94e6b1d7b
