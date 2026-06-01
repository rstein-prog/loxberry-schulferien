#!/bin/bash
set -e
echo "schulferien preinstall: checking Perl modules"
perl -MLWP::UserAgent -e 'exit 0' 2>/dev/null || cpanm --notest LWP::UserAgent 2>/dev/null || true
perl -MJSON::PP -e 'exit 0' 2>/dev/null || true
perl -MNet::MQTT::Simple -e 'exit 0' 2>/dev/null || cpanm --notest Net::MQTT::Simple 2>/dev/null || true
exit 0
