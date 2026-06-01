#!/usr/bin/env perl
use strict;
use warnings;

use FindBin;
use Cwd qw(abs_path);
use File::Basename qw(basename);
use File::Spec;
use JSON::PP qw(encode_json);

my $plugin_folder = basename($FindBin::Bin);
my $bin_dir       = abs_path($FindBin::Bin);
my $lb_home       = $ARGV[0] // $ENV{LBHOMEDIR} // $ENV{LB_HOME};
if (!$lb_home) {
    $lb_home = File::Spec->catdir($bin_dir, '..', '..', '..');
    $lb_home = abs_path($lb_home) || $lb_home;
}
$plugin_folder = $ARGV[1] if @ARGV > 1 && $ARGV[1] ne '';

unshift @INC, $bin_dir;

require Schulferien::Config;
require Schulferien::API;

my $cfg = Schulferien::Config::load($lb_home, $plugin_folder);
my $data_dir = File::Spec->catdir($lb_home, 'data', 'plugins', $plugin_folder);
mkdir $data_dir unless -d $data_dir;

my $state = Schulferien::Config::normalize_state($cfg->{state});
my ($status, $err) = Schulferien::API::build_status_for_state($state);
if (!$status) {
    print STDERR "refresh_state: failed for $state: " . ($err // 'unknown') . "\n";
    exit 1;
}

my $path = Schulferien::Config::state_store($data_dir);
open my $fh, '>', $path or do {
    print STDERR "refresh_state: cannot write $path: $!\n";
    exit 1;
};
print $fh encode_json($status);
close $fh;

print "refresh_state: updated $path for $state";
print " (partial: $err)" if $err;
print "\n";
exit 0;
