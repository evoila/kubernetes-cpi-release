#!/bin/bash
set -x

kubectl delete namespace bosh

rm -rf ../dev_releases/bosh-kubernetes-cpi/*.{yml,tgz}
rm -rf ./bosh-state.json ~/.bosh_init/installations/*
(
  cd ..
  scripts/sync-package-specs
  bosh -n create release --force --with-tarball
  sha1sum dev_releases/bosh-kubernetes-cpi/*.tgz
)

sleep 10
kubectl apply -f config.yml
