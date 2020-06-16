#!/bin/bash
set -euxo pipefail

source /etc/os-release

# Disable IPv6.
sudo sysctl -w net.ipv6.conf.all.disable_ipv6=1
echo "net.ipv6.conf.all.disable_ipv6=1" | sudo tee /etc/sysctl.d/psi-disable-ipv6.conf

# Disable sssd.
sudo systemctl disable --now sssd

# Deploy internal Fedora repositories.
if [[ $ID == fedora ]]; then
    sudo cp /tmp/fedora-internal.repo /etc/yum.repos.d/fedora-internal.repo
fi

# Subscribe RHEL 8 CDN instances.
if [[ $(uname -n) =~ rhel8cdn ]]; then
    sudo subscription-manager register \
        --serverurl=subscription.rhn.stage.redhat.com \
        --username="${RHN_USERNAME}" \
        --password="${RHN_PASSWORD}"
    sudo subscription-manager attach \
        --pool=8a99f9ac725604db017256b11f620666
    sudo subscription-manager repos \
        --enable=ansible-2.9-for-rhel-8-x86_64-rpms \
        --enable=openstack-16-tools-for-rhel-8-x86_64-rpms
fi

# Deploy RHEL 8.3 nightly repositories.
if [[ $(uname -n) =~ rhel83 ]]; then
    sudo curl -Lsk --output /etc/yum.repos.d/rhel8nightly.repo \
        https://gitlab.cee.redhat.com/snippets/2147/raw
fi

# Install EPEL repository RPM.
if [[ $ID == rhel ]]; then
    curl -Ls --output /tmp/epel.rpm \
        https://dl.fedoraproject.org/pub/epel/epel-release-latest-8.noarch.rpm
    sudo rpm -Uvh /tmp/epel.rpm
    rm -f /tmp/epel.rpm
fi

# Upgrade all packages.
sudo dnf -y upgrade

# Install the minimal package set.
sudo dnf -y install chrony git java-1.8.0-openjdk-headless

# Deploy customized mock templates.
if [[ $ID == fedora ]]; then
    sudo cp /tmp/fedora-branched.tpl /etc/mock/templates/fedora-branched.tpl
fi
if [[ $(uname -n) =~ rhel83 ]]; then
    sudo cp /tmp/rhel-8.tpl /etc/mock/templates/rhel-8.tpl
    cat /etc/yum.repos.d/rhel8nightly.repo | \
        sudo tee -a /etc/mock/templates/rhel-8.tpl
fi

# Set up a swapfile.
sudo fallocate -l 1G /swapfile
sudo chmod 0600 /swapfile
sudo mkswap /swapfile
sudo swapon /swapfile
echo "/swapfile none swap sw 0 0" | sudo tee -a /etc/fstab

# Prepare a directory for Jenkins.
sudo mkdir /jenkins
sudo chmod 0777 /jenkins

# Configure chrony.
sudo sed 's/^pool.*/pool clock.corp.redhat.com iburst/'
sudo systemctl enable chronyd