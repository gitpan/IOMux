# Copyrights 2011 by Mark Overmeer.
#  For other contributors see ChangeLog.
# See the manual pages for details on the licensing terms.
# Pod stripped from pm file by OODoc 1.07.
use warnings;
use strict;

package IOMux::File::Read;
use vars '$VERSION';
$VERSION = '0.12';

use base 'IOMux::Handler::Read';

use Log::Report    'iomux';
use Fcntl;
use File::Basename 'basename';


sub init($)
{   my ($self, $args) = @_;

    my $file  = $args->{file}
        or error __x"no file to open specified in {pkg}", pkg => __PACKAGE__;

    my $flags = $args->{modeflags};
    unless(ref $file || defined $flags)
    {   $flags  = O_RDONLY|O_NONBLOCK;
        $flags |= O_EXCL   if $args->{exclusive};
    }

    my $fh;
    if(ref $file)
    {   $fh = $file;
        $self->{IMFR_mode} = $args->{mode} || '<';
    }
    else
    {   sysopen $fh, $file, $flags
            or fault __x"cannot open file {fn} for {pkg}"
               , fn => $file, pkg => __PACKAGE__;
        $self->{IMFR_mode} = $flags;
    }
    $args->{name} = '<'.(basename $file);
    $args->{fh}   = $fh;

    $self->SUPER::init($args);
    $self;
}


sub open($$@)
{   my ($class, $mode, $file, %args) = @_;
    $class->new(file => $file, mode => $mode, %args);
}

#-------------------

sub mode() {shift->{IMFR_mode}}

1;
