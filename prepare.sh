#!/bin/bash
set -euo pipefail

# Get data from os-release
source /etc/os-release

# Check if we are on the internal network or not.
INTERNAL=no
if curl -s --fail https://gitlab.cee.redhat.com 2>&1 > /dev/null; then
  INTERNAL=yes
fi

# Configure dnf.
echo "fastestmirror=1" >> /etc/dnf/dnf.conf
echo "install_weak_deps=0" >> /etc/dnf/dnf.conf
rm -f /etc/yum.repos.d/fedora*modular*

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

# Download RHEL 8 repositories if needed.
if [[ $ID == "rhel" ]]; then

  if [[ $VERSION_ID == "8.2" ]]; then
    curl --retry 5 -kLso /etc/yum.repos.d/rhel8.repo \
      https://gitlab.cee.redhat.com/snippets/2143/raw

  elif [[ $VERSION_ID == "8.3" ]]; then
    curl --retry 5 -kLso /etc/yum.repos.d/rhel8.repo \
      https://gitlab.cee.redhat.com/snippets/2147/raw
  fi

  # Add the EPEL repository.
  curl --retry 5 -Lso /tmp/epel8.rpm \
    https://dl.fedoraproject.org/pub/epel/epel-release-latest-8.noarch.rpm
  rpm -Uvh --quiet /tmp/epel8.rpm
  rm -f /tmp/epel8.rpm
fi

# Add extra packages depending on the OS.
if [[ $ID == 'rhel' ]]; then
  EXTRA_PACKAGES="systemd-timesyncd"
fi
if [[ $ID == 'fedora' ]]; then
  EXTRA_PACKAGES="python3-openstackclient"
fi

# Upgrade and install packages.
dnf -y shell << EOF
upgrade
install ansible createrepo_c dnf-plugins-core git htop
install java-1.8.0-openjdk-headless make mock podman
install policycoreutils-python-utils python3 python3-pip rpm-build
install vi vim xz ${EXTRA_PACKAGES:-}
transaction run
EOF

# Update the mock templates depending on the OS.
if [[ $INTERNAL == yes ]] && [[ $ID == 'rhel' ]]; then
  mv /tmp/rhel-8.tpl /etc/mock/templates/
fi
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

# Ensure modular repositories are removed.
rm -f /etc/yum.repos.d/fedora*modular*

# Set up time synchronization.
sed -i 's/^#NTP=.*/NTP=clock.corp.redhat.com/' /etc/systemd/timesyncd.conf
systemctl disable chronyd || true
systemctl enable systemd-timesyncd

# Install netdata for performance monitoring.
# bash <(curl -Ss https://my-netdata.io/kickstart.sh) --dont-wait \
#   --no-updates --disable-telemetry --stable-channel --dont-start-it > /dev/null
# systemctl enable netdata

# Clean up.
dnf -y clean all
rm -rf /var/cache/dnf/
