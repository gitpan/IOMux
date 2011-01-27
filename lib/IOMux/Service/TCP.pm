# Copyrights 2011 by Mark Overmeer.
#  For other contributors see ChangeLog.
# See the manual pages for details on the licensing terms.
# Pod stripped from pm file by OODoc 1.07.
use warnings;
use strict;

package IOMux::Service::TCP;
use vars '$VERSION';
$VERSION = '0.12';

use base 'IOMux::Handler::Service';

use Log::Report 'iomux';
use IOMux::Net::TCP ();

use Socket 'SOCK_STREAM';


sub init($)
{   my ($self, $args) = @_;

    my $socket = $args->{fh}
      = (delete $args->{socket}) || $self->extractSocket($args);

    my $proto = $socket->socktype;
    $proto eq SOCK_STREAM
         or error __x"{pkg} needs STREAM protocol socket", pkg => ref $self;

    $args->{name} ||= "listen tcp ".$socket->sockhost.':'.$socket->sockport;

    $self->SUPER::init($args);

    my $ct = $self->{IMST_conn_type} = $args->{conn_type}
        or error __x"a conn_type for incoming request is need by {name}"
          , name => $self->name;

    $self->{IMST_conn_opts} = $args->{conn_opts} || [];
    $self;
}

#------------------------

sub clientType() {shift->{IMST_conn_type}}
sub socket()     {shift->fh}

#-------------------------

# The read flag is set on the socket, which means that a new connection
# attempt is made.

sub mux_read_flagged()
{   my $self = shift;

    if(my $client = $self->socket->accept)
    {   my $ct = $self->{IMST_conn_type};
        my $handler = ref $ct eq 'CODE'
          ? $ct->(socket => $client, @{$self->{IMST_conn_opts}})
          : $ct->new(socket => $client, @{$self->{IMST_conn_opts}});
        $self->mux->add($handler);
        $self->mux_connection($client);
    }
    else
    {   alert "accept for {name} failed", name => $self->name;
    }
}

1;
