#!/bin/bash
set -euxo pipefail

# Get data from os-release
source /etc/os-release

# Check partitions.
fdisk -l

# Configure dnf.
echo "fastestmirror=1" >> /etc/dnf/dnf.conf
echo "install_weak_deps=0" >> /etc/dnf/dnf.conf
rm -fv /etc/yum.repos.d/fedora*modular*

# Disable sssd as it's not needed.
systemctl disable --now sssd

# Upgrade system.
dnf -y upgrade

# Install required packages for Jenkins and other jobs.
dnf -y install ansible awscli buildah dnf-plugins-core git grubby htop \
  java-1.8.0-openjdk-headless podman python3 python3-pip rpm-build runc vim

# Prepare for the Docker installation.
grubby --update-kernel=ALL --args="systemd.unified_cgroup_hierarchy=0"
dnf -y config-manager \
  --add-repo https://download.docker.com/linux/fedora/docker-ce.repo

# Adjust the repo to use Fedora 31 for Fedora32+.
if [[ $VERSION_ID != '31' ]]; then
  sed -i 's/$releasever/31/' /etc/yum.repos.d/docker-ce.repo
fi

# Install Docker.
dnf -y install docker-ce docker-ce-cli containerd.io
systemctl enable docker

# Clean up.
dnf -y clean all
