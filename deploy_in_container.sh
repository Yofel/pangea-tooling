#!/bin/sh

set -ex

SCRIPTDIR=$(readlink -f $(dirname -- "$0"))

export DEBIAN_FRONTEND=noninteractive
export LANG=en_US.UTF-8

echo "LANG=$LANG" >> /etc/profile
echo "LANG=$LANG" >> /etc/environment

# FIXME: reneable
# echo 'Acquire::http { Proxy "http://10.0.3.1:3142"; };' > /etc/apt/apt.conf.d/00cache
echo 'Acquire::Languages "none";' > /etc/apt/apt.conf.d/00aptitude
echo 'APT::Color "1";' > /etc/apt/apt.conf.d/99color

# Switch to cloudfront for debian
sed -i 's,httpredir.debian.org,deb.debian.org,g' /etc/apt/sources.list
sed -i 's,ftp.debian.org,deb.debian.org,g' /etc/apt/sources.list

i="3"
while [ $i -gt 0 ]; do
  apt-get update && break
  i=$((i-1))
  sleep 60 # sleep a bit to give problem a chance to resolve
done

gem list -i rake
if [ $? -eq 0 ]; then
  gem uninstall rake
fi

ESSENTIAL_PACKAGES="rake ruby ruby-dev build-essential zlib1g-dev git-core"
i="5"
while [ $i -gt 0 ]; do
  apt-get -y -o APT::Get::force-yes=true -o Debug::pkgProblemResolver=true \
    install ${ESSENTIAL_PACKAGES} && break
  i=$((i-1))
done

# Bootstrap rake
if [ -e /usr/local/bin/ruby ]; then
  gem install rake
fi

which rake
which ruby

cd $SCRIPTDIR
rake -f deploy_in_container.rake align_ruby

exec rake -f deploy_in_container.rake deploy_in_container
