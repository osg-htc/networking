#!/bin/bash -xe

echo "Verifying mkdocs build"
PYTHONPATH=src/ mkdocs build -v
