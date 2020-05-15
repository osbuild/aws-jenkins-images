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
    curl --retry 5 -kLso /etc/yum.repos.d/rhel8.repo \
      https://gitlab.cee.redhat.com/snippets/2143/raw
  elif [[ $VERSION_ID == "8.3" ]]; then
    curl --retry 5 -kLso /etc/yum.repos.d/rhel8.repo \
      https://gitlab.cee.redhat.com/snippets/2147/raw
  fi
  curl --retry 5 -Lso /tmp/epel8.rpm \
    https://dl.fedoraproject.org/pub/epel/epel-release-latest-8.noarch.rpm
  rpm -Uvh /tmp/epel8.rpm
  rm -fv /tmp/epel8.rpm
fi

# Upgrade system.
dnf ${DNF_EXTRA_ARGS:-} -qy upgrade

# Add extra packages depending on the OS.
if [[ $ID == 'rhel' ]]; then
  EXTRA_PACKAGES="systemd-timesyncd"
fi

# Install required packages for Jenkins and other jobs.
dnf ${DNF_EXTRA_ARGS:-} -qy install \
  ansible buildah chrony createrepo_c dnf-plugins-core git htop \
  java-1.8.0-openjdk-headless make mock podman policycoreutils-python-utils \
  python3 python3-pip rpm-build vi vim xz ${EXTRA_PACKAGES:-}

# Prepare the mock chroot.
if [[ $PLATFORM_ID == "platform:el8" ]]; then
  mv /tmp/rhel-8.tpl /etc/mock/templates/rhel-8.tpl
  cat /etc/yum.repos.d/rhel8.repo | tee -a /etc/mock/templates/rhel-8.tpl
  echo '"""' | tee -a /etc/mock/templates/rhel-8.tpl
  export VERSION_ID=8
  cat /etc/mock/templates/rhel-8.tpl
fi
mock -r "${ID}-${VERSION_ID}-$(uname -m)" --no-bootstrap-chroot --init

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

# Set up time synchronization.
sed -i 's/^#NTP=.*/NTP=clock.corp.redhat.com/' /etc/systemd/timesyncd.conf
systemctl disable chronyd || true
systemctl enable systemd-timesyncd

# Install netdata for performance monitoring.
bash <(curl -Ss https://my-netdata.io/kickstart.sh) --dont-wait \
  --no-updates --disable-telemetry --stable-channel

# Clean up.
dnf -y clean all
