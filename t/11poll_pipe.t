#!/usr/bin/env perl
use warnings;
use strict;

use lib "lib", "../lib";
use Test::More;
use File::Temp qw/mktemp/;

#use Log::Report mode => 3;  # debugging

sub check_write();

BEGIN { eval "require IO::Poll";
        $@ and plan skip_all => "IO::Poll not installed";

        plan tests => 12;
      }

use_ok('IOMux::Poll');

my $mux = IOMux::Poll->new;
isa_ok($mux, 'IOMux::Poll');

my $tempfn = mktemp 'iomux-test.XXXXX';
ok(1, "tempfile = $tempfn");
check_write;

$mux->loop;
ok(1, 'clean exit of mux');

unlink $tempfn;

exit 0;
#####

sub check_write()
{   use_ok('IOMux::Pipe::Write');

    my $pw = IOMux::Pipe::Write->new(command => ['sort','-o',$tempfn]);
    isa_ok($pw, 'IOMux::Pipe::Write');
    my $pw2 = $mux->add($pw);

    $pw->write(\"tic\ntac\n");
    $pw->write(\"toe\n");
    $pw->close(\&written);
}

sub written($)
{   my $pw = shift;
    isa_ok($pw, 'IOMux::Pipe::Write');

#unlink $tempfn;
    use_ok('IOMux::Pipe::Read');
    my $pr = IOMux::Pipe::Read->new(command => ['cat', $tempfn ]);
    isa_ok($pr, 'IOMux::Pipe::Read');
    my $pr2 = $mux->add($pr);
    $pr->slurp(\&read_all);
}

sub read_all($$)
{   my ($pr, $bytes) = @_;
   isa_ok($pr, 'IOMux::Pipe::Read');
   is($$bytes, "tac\ntic\ntoe\n");
   $pr->close;
   ok($!==0);

   unlink $tempfn;
}
