#!/bin/bash
set -euxo pipefail

# Get data from os-release
source /etc/os-release

# Configure dnf.
echo "fastestmirror=1" >> /etc/dnf/dnf.conf
echo "install_weak_deps=0" >> /etc/dnf/dnf.conf
rm -fv /etc/yum.repos.d/fedora*modular*

# If we are in PSI, disable IPv6 to avoid routing problems.
if ! curl -s --fail https://gitlab.cee.redhat.com 2>&1 > /dev/null; then
  sysctl -w net.ipv6.conf.all.disable_ipv6=1
  echo "net.ipv6.conf.all.disable_ipv6=1" | tee /etc/sysctl.d/50-disable-ipv6.conf
fi

# Disable sssd as it's not needed.
systemctl disable --now sssd

# Download RHEL 8 repositories if needed.
if [[ $PLATFORM_ID == "platform:el8" ]]; then
  if [[ $VERSION_ID == "8.2" ]]; then
    curl --retry 5 -kLso /etc/yum.repos.d/rhel82.repo \
      https://gitlab.cee.redhat.com/snippets/2143/raw
  elif [[ $VERSION_ID == "8.3" ]]; then
    curl --retry 5 -kLso /etc/yum.repos.d/rhel83.repo \
      https://gitlab.cee.redhat.com/snippets/2147/raw
  fi
  curl --retry 5 -Lso /tmp/epel8.rpm \
    https://dl.fedoraproject.org/pub/epel/epel-release-latest-8.noarch.rpm
  rpm -Uvh /tmp/epel8.rpm
  rm -fv /tmp/epel8.rpm
fi

# Upgrade system.
dnf ${DNF_EXTRA_ARGS:-} -qy upgrade

# Install required packages for Jenkins and other jobs.
dnf ${DNF_EXTRA_ARGS:-} -qy install \
  ansible buildah dnf-plugins-core git htop java-1.8.0-openjdk-headless make \
  mock podman policycoreutils-python-utils python3 python3-pip rpm-build vi \
  vim xz

# Set up swap.
fallocate -l 1G /swapfile
chmod 0600 /swapfile
mkswap /swapfile
swapon /swapfile
echo '/swapfile none swap sw 0 0' | tee -a /etc/fstab

# Create the jenkins work directory.
mkdir /jenkins
chmod 0777 /jenkins

# Ensure /tmp is mounted on tmpfs.
systemctl enable tmp.mount || systemctl unmask tmp.mount && systemctl start tmp.mount

# Ensure modular repositories are removed.
rm -fv /etc/yum.repos.d/fedora*modular*

# Switch ssh to port 2222.
# sed -i 's/#Port 22/Port 2222/' /etc/ssh/sshd_config
# semanage port -a -t ssh_port_t -p tcp 2222

# Clean up.
dnf -y clean all
