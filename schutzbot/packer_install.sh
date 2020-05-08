#!/bin/bash
set -euxo pipefail

if [[ ! -x /usr/bin/unzip ]]; then
  dnf -qy install unzip
fi

curl --retry 5 -Lso /tmp/packer.zip \
    https://releases.hashicorp.com/packer/1.5.6/packer_1.5.6_linux_amd64.zip

pushd /tmp
  unzip packer.zip
  sudo cp packer /usr/bin/packer.io
  sudo chmod +x /usr/bin/packer.io
popd

sudo mkdir -p /etc/openstack
sudo cp $OPENSTACK_CLOUDS_YAML /etc/openstack/clouds.yaml
sudo chmod 0644 /etc/openstack/clouds.yaml