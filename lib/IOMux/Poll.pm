# Copyrights 2011 by Mark Overmeer.
#  For other contributors see ChangeLog.
# See the manual pages for details on the licensing terms.
# Pod stripped from pm file by OODoc 1.07.
use warnings;
use strict;

package IOMux::Poll;
use vars '$VERSION';
$VERSION = '0.12';

use base 'IOMux';

use Log::Report 'iomux';

use List::Util  'min';
use POSIX       'errno_h';
use IO::Poll;
use IO::Handle;

$SIG{PIPE} = 'IGNORE';   # pipes are handled in select


my $poll;
sub init($)
{   my ($self, $args) = @_;
    $self->SUPER::init($args);
    $poll ||= IO::Poll->new;
    $self;
}

#-------------

sub poller {$poll}

#-------------

sub fdset($$$$$)
{   my ($self, $fileno, $state, $r, $w, $e) = @_;
    my $conn = $self->handler($fileno) or return;
    my $fh   = $conn->fh;
    my $mask = $poll->mask($fh);
    if($state==0)
    {   $mask &= ~POLLIN  if $r;
        $mask &= ~POLLOUT if $w;
        $mask &= ~POLLERR if $e;
    }
    else
    {   $mask |=  POLLIN  if $r;
        $mask |=  POLLOUT if $w;
        $mask |=  POLLERR if $e;
    }
    $poll->mask($fh, $mask);
}

sub one_go($$)
{   my ($self, $wait, $heartbeat) = @_;

    my $numready = $poll->poll($wait);

    $heartbeat->($self, $numready, undef)
        if $heartbeat;

    if($numready < 0)
    {   return if $! == EINTR || $! == EAGAIN;
        alert "Leaving loop with $!";
        return 0;
    }

    $numready
        or return 1;
 
    $self->_ready(mux_read_flagged   => POLLIN|POLLHUP);
    $self->_ready(mux_write_flagged  => POLLOUT);
    $self->_ready(mux_except_flagged => POLLERR);

    1;  # success
}

# It would be nice to have an algorithm which is better than O(n)
sub _ready($$)
{   my ($self, $call, $mask) = @_;
    my $handlers = $self->_handlers;
    foreach my $fh ($poll->handles($mask))
    {   my $fileno = $fh->fileno or next;   # close filehandle
        if(my $conn = $handlers->{$fileno})
        {   # filehandle flagged
            $conn->$call($fileno);
        }
        else
        {   # Handler administration error, but when write and error it may
            # be caused by read errors.
            alert "connection for ".$fh->fileno." not registered in $call"
                if $call eq 'mux_read_flagged';
        }
    }
}

1;

__END__
