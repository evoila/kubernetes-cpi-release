#!/bin/bash
set -e

BASE_DIR=$PWD/scripts/deployment
BOSH_DEPLOYMENT=$BASE_DIR/bosh-deployment
echo "Working directory: $BASE_DIR"
echo "Bosh directory: $BOSH_DEPLOYMENT"

pushd $BASE_DIR
  mkdir -p bosh-env
  if [ ! -f bosh-env/bosh.key.pub ]; then
    ssh-keygen -t rsa -b 4096 -C "vcap" -N "" -f bosh-env/bosh.key
  fi
 echo "Creating bosh env"
 bosh create-env \
    $BOSH_DEPLOYMENT/bosh.yml \
    -o $BASE_DIR/kubernetes-cpi/cpi.yml \
    -o $BOSH_DEPLOYMENT/jumpbox-user.yml \
    -o $BOSH_DEPLOYMENT/uaa.yml \
    -o $BASE_DIR/kubernetes-cpi/mod-uaa.yml \
    -o $BOSH_DEPLOYMENT/credhub.yml \
    -o $BASE_DIR/kubernetes-cpi/mod-credhub.yml \
    --state ./bosh-env/state.json \
    --vars-store ./bosh-env/creds.yml \
    --var-file=vcap_public_key=bosh-env/bosh.key.pub \
    -v director_name="kubernetes" \
    -v cpi_path="<path to cpi release>" \
    -v stemcell_path="<path to stemcell>" \
    -v internal_ip="<bosh-internal service ip>" \
    -v node_ip="<ip to kubernetes node with kube-proxy running>" \
    -v kube_apiserver="<kube_apiserver_ip:port>" \
    --var-file=ca_data=$BASE_DIR/kubeconfig/ca_data \
    --var-file=client_data=$BASE_DIR/kubeconfig/client_data \
    --var-file=client_key=$BASE_DIR/kubeconfig/client_key \
    -v create_env_port=31000
    
  echo "Creating env alias: kubernetes"
  bosh -e <ip to kubernetes node with kube-proxy running>:31001 \
      --ca-cert <(bosh int ./bosh-env/creds.yml --path /director_ssl/ca) \
      alias-env kubernetes

  cat <<'EOF' > ./bosh-env/.envrc
export BOSH_ENVIRONMENT=kubernetes
export BOSH_CLIENT=admin
export BOSH_CLIENT_SECRET=$(bosh int ./creds.yml --path /admin_password)
EOF
popd