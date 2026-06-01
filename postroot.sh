#!/bin/bash

set -e

APT_PACKAGES=(
  libnet-mqtt-simple-perl
  libwww-perl
  liburi-perl
)

PERL_MODULES=(
  Net::MQTT::Simple
  LWP::UserAgent
  URI::Escape
)

is_pkg_installed() {
  dpkg-query -W -f='${Status}' "$1" 2>/dev/null | grep -q 'ok installed'
}

missing=()
for pkg in "${APT_PACKAGES[@]}"; do
  if is_pkg_installed "$pkg"; then
    echo "<INFO> Package already installed: $pkg"
  else
    echo "<INFO> Package missing: $pkg"
    missing+=("$pkg")
  fi
done

if [ ${#missing[@]} -gt 0 ]; then
  echo "<INFO> Installing missing packages: ${missing[*]}"
  export DEBIAN_FRONTEND=noninteractive
  export APT_LISTCHANGES_FRONTEND=none
  apt-get -qq update
  apt-get -y --no-install-recommends install "${missing[@]}"
  echo "<OK> Installed: ${missing[*]}"
else
  echo "<OK> All APT dependencies already installed — skipping apt update/install"
fi

for mod in "${PERL_MODULES[@]}"; do
  if perl -M"$mod" -e 'exit 0' 2>/dev/null; then
    echo "<INFO> Perl module already available: $mod"
  else
    echo "<WARN> Perl module $mod still missing — trying cpanm fallback"
    cpanm --notest "$mod" 2>/dev/null || true
  fi
done

exit 0
