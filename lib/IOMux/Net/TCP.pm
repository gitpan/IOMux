# Copyrights 2011 by Mark Overmeer.
#  For other contributors see ChangeLog.
# See the manual pages for details on the licensing terms.
# Pod stripped from pm file by OODoc 1.07.
use warnings;
use strict;

package IOMux::Net::TCP;
use vars '$VERSION';
$VERSION = '0.12';

use base 'IOMux::Handler::Read', 'IOMux::Handler::Write';

use Log::Report 'iomux';
use Socket      'SOCK_STREAM';
use IO::Socket::INET;


sub init($)
{   my ($self, $args) = @_;
    my $socket = $args->{fh}
      = (delete $args->{socket}) || $self->extractSocket($args);

    $args->{name} ||= "tcp ".$socket->peerhost.':'.$socket->peerport;

    $self->IOMux::Handler::Read::init($args);
    $self->IOMux::Handler::Write::init($args);

    $self;
}

#-------------------

sub socket() {shift->fh}

#-------------------

sub shutdown($)
{   my($self, $which) = @_;
    my $socket = $self->socket;
    my $mux    = $self->mux;

    if($which!=1)
    {   # Shutdown for reading.  We can do this now.
        $socket->shutdown(0);
        $self->{IMNT_shutread} = 1;
        # The mux_eof hook must be run from the main loop to consume
        # the rest of the inbuffer if there is anything left.
        # It will also remove $fh from _readers.
        $self->fdset(0, 1, 0, 0);
    }
    if($which!=0)
    {   # Shutdown for writing.  Only do this now if there is no pending data.
        $self->{IMNT_shutwrite} = 1;
        unless($self->mux_output_waiting)
        {   $socket->shutdown(1);
            $self->fdset(0, 0, 1, 0);
        }
    }

    $self->close
        if $self->{IMNT_shutread}
        && $self->{IMNT_shutwrite} && !$self->mux_output_waiting;
}

sub close()
{   my $self = shift;

    warning __x"closing {name} with read buffer", name => $self->name
        if length $self->{ICMT_inbuf};

    warning __x"closing {name} with write buffer", name => $self->name
        if $self->{ICMT_outbuf};

    $self->socket->close;
    $self->SUPER::close;
}

#-------------------------

sub mux_init($)
{   my ($self, $mux) = @_;
    $self->SUPER::mux_init($mux);
    $self->fdset(1, 1, 1, 0);
}

sub mux_remove()
{   my $self = shift;
    $self->SUPER::mux_remove;
}

sub mux_outbuffer_empty()
{   my $self = shift;
    $self->SUPER::mux_outbuffer_empty;

    if($self->{IMNT_shutwrite} && !$self->mux_output_waiting)
    {   $self->socket->shutdown(1);
        $self->fdset(0, 0, 1, 0);
        $self->close if $self->{IMNT_shutread};
    }
}


1;
