#!/bin/bash
set -euxo pipefail

# We need unzip for the packer installation
if [[ ! -x /usr/bin/unzip ]]; then
  dnf -qy install unzip
fi

# Download the packer zip file.
curl --retry 5 -Lso /tmp/packer.zip \
    https://releases.hashicorp.com/packer/1.5.6/packer_1.5.6_linux_amd64.zip

# Install packer.
pushd /tmp
  unzip packer.zip
  sudo cp packer /usr/bin/packer.io
  sudo chmod +x /usr/bin/packer.io
popd

# Deploy OpenStack credentials.
sudo mkdir -p /etc/openstack
sudo cp $OPENSTACK_CLOUDS_YAML /etc/openstack/clouds.yaml
sudo chmod 0644 /etc/openstack/clouds.yaml
