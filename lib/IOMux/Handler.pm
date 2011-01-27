# Copyrights 2011 by Mark Overmeer.
#  For other contributors see ChangeLog.
# See the manual pages for details on the licensing terms.
# Pod stripped from pm file by OODoc 1.07.
use warnings;
use strict;

package IOMux::Handler;
use vars '$VERSION';
$VERSION = '0.12';


use Log::Report  'iomux';

use Scalar::Util     'weaken';
use Time::HiRes      'time';
use Socket;
use Fcntl;

my $start_time = time;


sub new(@)  {my $class = shift; (bless {}, $class)->init( {@_} ) }

sub init($)
{   my ($self, $args) = @_;
    return $self if $self->{IMH_name}; # already initialized

    my $name = $self->{IMH_name} = $args->{name} || "$self";
    if(my $fh = $self->{IMH_fh} = $args->{fh})
    {   $self->{IMH_fileno}   = $fh->fileno;
        $self->{IMH_uses_ssl} = UNIVERSAL::isa($fh, 'IO::Socket::SSL');
    }
    $self;
}


sub open() {panic}

#-------------------------

sub name()   {shift->{IMH_name}}
sub mux()    {shift->{IMH_mux}}


sub fileno() {shift->{IMH_fileno}}
sub fh()     {shift->{IMH_fh}}
sub usesSSL(){shift->{IMH_uses_ssl}}

#-----------------------

sub timeout(;$)
{   my $self  = shift;
    @_ or return $self->{IMH_timeout};

    my $old   = $self->{IMH_timeout};
    my $after = shift;
    my $when  = !$after      ? undef
      : $after > $start_time ? $after
      :                        ($after + time);
    $self->{IMH_mux}->changeTimeout($self->{IMH_fileno}, $old, $when);
    $self->{IMH_timeout} = $when;
}


sub close(;$)
{   my ($self, $cb) = @_;
    if(my $fh = delete $self->{IMH_fh})
    {   if(my $mux = $self->{IMH_mux})
        {   $mux->remove($self->{IMH_fileno});
        }
        $fh->close;
    }
    local $!;
    $cb->($self) if $cb;
}  

#-------------------------

sub mux_init($;$)
{   my ($self, $mux, $handler) = @_;

    $self->{IMH_mux} = $mux;
    weaken($self->{IMH_mux});

    my $fileno = $self->{IMH_fileno};
    $mux->handler($fileno, $handler || $self);

    if(my $timeout = $self->{IMH_timeout})
    {   $mux->changeTimeout($fileno, undef, $timeout);
    }

    trace "mux add #$fileno, $self->{IMH_name}";
}


sub mux_remove()
{   my $self = shift;
    delete $self->{IMH_mux};
    trace "mux remove #$self->{IMH_fileno}, $self->{IMH_name}";
}


sub mux_timeout()
{   my $self = shift;
    error __x"timeout set on {name} but not handled", name => $self->name;
}

#----------------------


sub mux_read_flagged($)  { panic "no input expected on ". shift->name }


sub mux_except_flagged($)  { panic "exception arrived on ". shift->name }


sub mux_write_flagged($) { shift }  # simply ignore write offers


#-------------------------

sub show()
{   my $self = shift;
    my $name = $self->name;
    my $fh   = $self->fh
        or return "fileno=".$self->fileno." is closed; name=$name";

    my $mode = 'unknown';
    unless($^O eq 'Win32')
    {   my $flags = fcntl $fh, F_GETFL, 0       or fault "fcntl F_GETFL";
        $mode = ($flags & O_WRONLY) ? 'w'
              : ($flags & O_RDONLY) ? 'r'
              : ($flags & O_RDWR)   ? 'rw'
              :                       'p';
    }

    my @show = ("fileno=".$fh->fileno, "mode=$mode");
    if(my $sockopts  = getsockopt $fh, SOL_SOCKET, SO_TYPE)
    {   # socket
        my $type = unpack "i", $sockopts;
        my $kind = $type==SOCK_DGRAM ? 'UDP' : $type==SOCK_STREAM ? 'TCP'
          : 'unknown';
        push @show, "sock=$kind";
    }

    join ", ", @show, "name=$name";
}


sub fdset($$$$)
{   my $self = shift;
    $self->{IMH_mux}->fdset($self->{IMH_fileno}, @_);
}


sub extractSocket($)
{   my ($thing, $args) = @_;
    my $class  = ref $thing || $thing;

    my $socket = delete $args->{socket};
    return $socket if $socket;

    my @sockopts;
    push @sockopts, $_ => delete $args->{$_}
        for grep /^[A-Z]/, keys %$args;

    @sockopts
       or error __x"pass socket or provide parameters to create one for {pkg}"
          , pkg => $class;

    my $ssl  = delete $args->{use_ssl};

    # the extension will load these classes
    my $make = $ssl ? 'IO::Socket::SSL' : 'IO::Socket::INET';
    $socket  = $make->new(Blocking => 0, @sockopts)
        or fault __x"cannot create {pkg} socket", pkg => $class;

    $socket;
}

1;
