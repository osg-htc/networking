#!/bin/bash -xe

openssl aes-256-cbc -K $encrypted_ddf41a3258e2_key -iv $encrypted_ddf41a3258e2_iv -in deploy-key.enc -out deploy-key -d
chmod 600 deploy-key
eval `ssh-agent -s`
ssh-add deploy-key
git config user.name "Automatic Publish"
git config user.email "blin@cs.wisc.edu"
git remote add gh-token "${GH_REF}";
git fetch gh-token && git fetch gh-token gh-pages:gh-pages
echo "Pushing to github"
PYTHONPATH=src/ mkdocs gh-deploy -v --clean --remote-name gh-token
git push gh-token gh-pages
