# Copyrights 2011 by Mark Overmeer.
#  For other contributors see ChangeLog.
# See the manual pages for details on the licensing terms.
# Pod stripped from pm file by OODoc 1.07.
use warnings;
use strict;

package IOMux::Handler::Read;
use vars '$VERSION';
$VERSION = '0.12';

use base 'IOMux::Handler';

use Log::Report    'iomux';
use Fcntl;
use POSIX          'errno_h';
use File::Basename 'basename';


sub init($)
{   my ($self, $args) = @_;
    $self->SUPER::init($args);
    $self->{IMHR_read_size} = $args->{read_size} || 32768;
    $self->{IMHR_inbuf}     = '';
    $self;
}

#-------------------

sub readSize(;$)
{   my $self = shift;
    @_ ? $self->{IMHR_read_size} = shift : $self->{IMHR_read_size};
}

#-----------------------

sub readline($)
{   my ($self, $cb) = @_;
    if($self->{IMHR_inbuf} =~ s/^([^\r\n]*)(?:\r?\n)//)
    {   return $cb->($self, "$1\n");
    }
    if($self->{IMHR_eof})
    {   # eof already before readline and no trailing nl
        my $line = $self->{IMHR_inbuf};
        $self->{IMHR_inbuf} = '';
        return $cb->($self, $line);
    }

    $self->{IMHR_read_more} = sub
      { my ($in, $eof) = @_;
        if($eof)
        {   delete $self->{IMHR_read_more};
            my $line = $self->{IMHR_inbuf};
            $self->{IMHR_inbuf} = '';
            return $cb->($self, $line);
        }
        ${$_[0]} =~ s/^([^\r\n]*)\r?\n//
            or return;
        delete $self->{IMHR_read_more};
        $cb->($self, "$1\n");
      };
}


sub slurp($)
{   my ($self, $cb) = @_;

    if($self->{IMHR_eof})   # eof already before readline
    {   my $in    = $self->{IMHR_inbuf} or return $cb->($self, \'');
        my $bytes = $$in;  # does copy the bytes. Cannot help it easily
        $$in      = '';
        return $cb->($self, \$bytes);
    }

    $self->{IMHR_read_more} = sub
      { my ($in, $eof) = @_;
        $eof or return;
        delete $self->{IMHR_read_more};
        my $bytes = $$in;  # does copy the bytes
        $$in      = '';
        $cb->($self, \$bytes);
      };
}

#-------------------------

sub mux_init($)
{   my ($self, $mux) = @_;
    $self->SUPER::mux_init($mux);
    $self->fdset(1, 1, 0, 0);
}

sub mux_read_flagged($)
{   my $self = shift;

    my $bytes_read
      = sysread $self->fh, $self->{IMHR_inbuf}, $self->{IMHR_read_size}
         , length($self->{IMHR_inbuf});

    if($bytes_read) # > 0
    {   $self->mux_input(\$self->{IMHR_inbuf});
    }
    elsif(defined $bytes_read)   # == 0
    {   $self->fdset(0, 1, 0, 0);
        $self->mux_eof(\$self->{IMHR_inbuf});
    }
    elsif($!==EINTR || $!==EAGAIN || $!==EWOULDBLOCK)
    {   # a bit unexpected, but ok
    }
    else
    {   warning __x"read from {name} closed unexpectedly: {err}"
          , name => $self->name, err => $!;
        $self->close;
    }
}


sub mux_input($)
{   my ($self, $inbuf) = @_;
    return $self->{IMHR_read_more}->($inbuf, 0)
        if $self->{IMHR_read_more};
}


sub mux_eof($)
{   my ($self, $inbuf) = @_;
    $self->{IMHR_eof}   = 1;
    $self->{IMHR_read_more}->($inbuf, 1)
        if $self->{IMHR_read_more};
}

1;
