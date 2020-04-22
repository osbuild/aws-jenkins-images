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

# BZ 1822030 workaround.
if [[ $NAME == "Fedora" ]] && [[ $VERSION_ID == 32 ]]; then
  DNF_EXTRA_ARGS="--enablerepo=updates-testing"
fi

# Upgrade system.
dnf ${DNF_EXTRA_ARGS:-} -y upgrade

# Install required packages for Jenkins and other jobs.
dnf ${DNF_EXTRA_ARGS:-} -y install \
  ansible awscli buildah cockpit-composer dnf-plugins-core git \
  grubby htop java-1.8.0-openjdk-headless libappstream-glib make npm podman \
  policycoreutils-python-utils python3 python3-pip rpm-build runc vim xz

# Ensure build dependencies for osbuild and osbuild-composer are included.
curl -o /tmp/osbuild-composer.spec \
  https://raw.githubusercontent.com/osbuild/osbuild-composer/master/osbuild-composer.spec
curl -o /tmp/osbuild.spec \
  https://raw.githubusercontent.com/osbuild/osbuild/master/osbuild.spec
dnf -y builddep /tmp/osbuild-composer.spec /tmp/osbuild.spec
rm -fv /tmp/*.spec

# Prepare for the Docker installation.
# grubby --update-kernel=ALL --args="systemd.unified_cgroup_hierarchy=0"
# dnf -y config-manager \
#   --add-repo https://download.docker.com/linux/fedora/docker-ce.repo

# Adjust the repo to use Fedora 31 for Fedora32+.
if [[ $VERSION_ID != '31' ]]; then
  sed -i 's/$releasever/31/' /etc/yum.repos.d/docker-ce.repo
fi

# Install Docker.
# dnf -y install docker-ce docker-ce-cli containerd.io
# systemctl enable docker

# Set up swap.
fallocate -l 1G /swapfile
chmod 0600 /swapfile
mkswap /swapfile
swapon /swapfile
echo '/swapfile none swap sw 0 0' | tee -a /etc/fstab

# Switch ssh to port 2222.
sed -i 's/#Port 22/Port 2222/' /etc/ssh/sshd_config
semanage port -a -t ssh_port_t -p tcp 2222

# Ensure we have journald running on reboot.
systemctl enable journald

# Clean up.
dnf -y clean all
