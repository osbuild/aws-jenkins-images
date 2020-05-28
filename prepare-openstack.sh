#!/bin/bash
set -euxo pipefail

# Get data from os-release
source /etc/os-release
HOSTNAME=$(uname -n)

# Check if we are on the internal network or not.
INTERNAL=no
if curl -s --fail https://gitlab.cee.redhat.com 2>&1 > /dev/null; then
  INTERNAL=yes
fi

# Disable IPv6 if we are on the internal network.
if [[ $INTERNAL == yes ]]; then
  sysctl -w net.ipv6.conf.all.disable_ipv6=1
  echo "net.ipv6.conf.all.disable_ipv6=1" | tee /etc/sysctl.d/50-disable-ipv6.conf
fi

# Configure internal Fedora repos if we are on the internal network.
if [[ $INTERNAL == yes ]] && [[ $ID == 'fedora' ]]; then
    cp /tmp/fedora-internal.repo /etc/yum.repos.d/
fi

# Disable sssd as it's not needed.
systemctl disable --now sssd

# Subscribe RHEL 8 if we're building a CDN image.
if [[ $HOSTNAME == *"rhel8cdn"* ]]; then
  # Register the instance.
  subscription-manager register \
    --serverurl=subscription.rhn.stage.redhat.com \
    --username $RHN_USERNAME \
    --password $RHN_PASSWORD
  # Attach a basic RHEL subscription.
  subscription-manager attach --pool=8a99f9ac725604db017256b11f620666
  # For Ansible, of course.
  subscription-manager repos --enable ansible-2.9-for-rhel-8-x86_64-rpms
  # For openstackclient.
  subscription-manager repos --enable openstack-16-tools-for-rhel-8-x86_64-rpms
fi

# Add nightly RHEL 8.2 repositories.
if [[ $HOSTNAME == *"rhel82"* ]]; then
  curl --retry 5 -kLso /etc/yum.repos.d/rhel8.repo \
    https://gitlab.cee.redhat.com/snippets/2143/raw

  # Update mock template.
  mv /tmp/rhel-8.tpl /etc/mock/templates/
fi

# Add nightly RHEL 8.3 repositories.
if [[ $HOSTNAME == *"rhel83"* ]]; then
  curl --retry 5 -kLso /etc/yum.repos.d/rhel8.repo \
    https://gitlab.cee.redhat.com/snippets/2147/raw

  # Update mock template.
  mv /tmp/rhel-8.tpl /etc/mock/templates/
fi

# All RHEL images need EPEL for mock.
if [[ $ID == 'rhel' ]]; then
  # Add the EPEL repository.
  curl --retry 5 -Lso /tmp/epel8.rpm \
    https://dl.fedoraproject.org/pub/epel/epel-release-latest-8.noarch.rpm
  rpm -Uvh --quiet /tmp/epel8.rpm
  rm -f /tmp/epel8.rpm
fi

# Upgrade and install packages.
dnf -y upgrade
dnf -y install ansible createrepo_c chrony dnf-plugins-core git \
  java-1.8.0-openjdk-headless make mock podman policycoreutils-python-utils \
  python3 python3-pip python3-openstackclient rpm-build vi vim \
  xz ${EXTRA_PACKAGES:-}
dnf clean packages
dnf clean all

# Disable modular repos on Fedora.
if [[ $ID == 'fedora' ]]; then
    dnf config-manager --set-disabled fedora-modular
    dnf config-manager --set-disabled updates-modular
fi

# Update the mock templates depending on the OS.
if [[ $INTERNAL == yes ]] && [[ $ID == 'fedora' ]]; then
  mv /tmp/fedora-branched.tpl /etc/mock/templates/fedora-branched.tpl
fi

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
systemctl unmask tmp.mount || true

# Set up time synchronization.
sed -i '/^pool/d' /etc/chrony.conf
echo "pool clock.corp.redhat.com iburst" >> /etc/chrony.conf
systemctl enable --now chronyd

# Install netdata for performance monitoring.
# bash <(curl -Ss https://my-netdata.io/kickstart.sh) --dont-wait \
#   --no-updates --disable-telemetry --stable-channel --dont-start-it > /dev/null
# systemctl enable netdata