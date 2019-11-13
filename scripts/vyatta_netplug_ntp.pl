#! /usr/bin/perl

#----- Copyright & License -----
#
# Copyright (C) 2018-2019 AT&T Intellectual Property.
# All Rights Reserved.
#
# SPDX-License-Identifier: GPL-2.0-only
#
#----- Copyright & License -----

use lib "/opt/vyatta/share/perl5/";
use Getopt::Long;
use Vyatta::Configd;
use Vyatta::Interface;
use Vyatta::Misc;
use NetAddr::IP;
use File::Copy;

my ( $operation, $dev, $proto, $addr, $vrf );

GetOptions(
    "operation=s" => \$operation,
    "dev=s"       => \$dev,
    "proto=s"     => \$proto,
    "addr=s"      => \$addr,
);

sub delete_listen_addr {
    my $ntp_path = "/run/ntp/vrf/$vrf";
    my $filename = "$ntp_path/ntp.conf";
    my $found    = 0;

    open my $in, '<', $filename or die "Can't read NTP conf(newaddr): $!";
    open my $out, '>', "$filename.new"
      or die "Can't update NTP conf(newaddr): $!";

    while (<$in>) {
        my $input = $_;
        if ( $input =~ /interface/ ) {
            $found++;
            if ( $_ =~ /listen $addr/ ) {
                $found--;
                next;
            }
            print $out $input;
        } else {
            if ( ( $input =~ /keys/ ) && ( $found == 0 ) ) {
                print $out "interface drop all\n";
            }
            print $out $_;
        }
    }
    close $out;
    close $in;
    unlink $filename;
    move( "$filename.new", $filename );
}

sub update_listen_addr {
    my $ntp_path = "/run/ntp/vrf/$vrf";
    my $filename = "$ntp_path/ntp.conf";

    open my $in, '<', $filename or die "Can't read NTP conf(newaddr): $!";
    open my $out, '>', "$filename.new"
      or die "Can't update NTP conf(newaddr): $!";

    while (<$in>) {
        if ( $_ =~ /interface drop/ ) {
            print $out "interface listen $addr\n";
        } else {
            print $out $_;
        }
    }
    close $out;
    close $in;
    unlink $filename;
    move( "$filename.new", $filename );
}

sub restart_ntpd {
    my $str =
`/opt/vyatta/sbin/vyatta_update_ntpsrcIntf.pl --rtinstance=$vrf --operation=get`;
    my ( $srcIntf, $af ) = split /:/, $str;

    if ( ( $srcIntf eq $dev ) && ( $af eq $proto ) ) {
        if ( $operation eq "set" ) {
            update_listen_addr();
        } elsif ( $operation eq "del" ) {
            delete_listen_addr();
        }
        system(
"/opt/vyatta/sbin/vyatta_configure_ntp.pl --operation=restart_trigger --rtinstance=$vrf"
        );
    }
    exit 0;
}

# find out which VRF the $dev belongs to
sub get_vrf {
    my $intf = new Vyatta::Interface($dev);
    $intf or die "Unknown interface name or type: $dev\n";
    my $vrf_name = $intf->vrf();

    return $vrf_name;
}

$vrf = get_vrf();
exit 0 unless -e "/run/ntp/vrf/$vrf/ntp.srcIntf";

restart_ntpd($operation);
exit 0;

