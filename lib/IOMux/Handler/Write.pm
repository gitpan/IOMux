# Copyrights 2011 by Mark Overmeer.
#  For other contributors see ChangeLog.
# See the manual pages for details on the licensing terms.
# Pod stripped from pm file by OODoc 1.07.
use warnings;
use strict;

package IOMux::Handler::Write;
use vars '$VERSION';
$VERSION = '0.12';

use base 'IOMux::Handler';

use Log::Report 'iomux';
use Fcntl;
use POSIX 'errno_h';
use File::Spec       ();;
use File::Basename   'basename';

use constant PIPE_BUF_SIZE => 4096;


sub init($)
{   my ($self, $args) = @_;
    $self->SUPER::init($args);
    $self->{IMHW_write_size} = $args->{write_size} || 4096;
    $self;
}

#-------------------

sub writeSize(;$)
{   my $self = shift;
    @_ ? $self->{IMHW_write_size} = shift : $self->{IMHW_write_size};
}

#-----------------------

sub print(@)
{   my $self = shift;
    $self->write( !ref $_[0] ? (@_>1 ? \join('',@_) : \shift)
                : ref $_[0] eq 'ARRAY' ? \join('',@{$_[0]}) : $_[0] );
}


sub say(@)
{   my $self = shift;
    $self->write
      ( !ref $_[0] ? \join('',@_, "\n")
      : ref $_[0] eq 'ARRAY' ? \join('',@{$_[0]}, "\n")
      : $_[0]."\n"
      );
}


sub printf($@)
{   my $self = shift;
    $self->write(\sprintf(@_));
}


sub write($;$)
{   my ($self, $blob, $more) = @_;

    if(exists $self->{IMHW_outbuf})
    {   ${$self->{IMHW_outbuf}} .= $$blob;
        $self->{IMHW_more} = $more;
        return;
    }

    my $bytes_written = syswrite $self->fh, $$blob, $self->{IMHW_write_size};
    if(!defined $bytes_written)
    {   return if $!==EWOULDBLOCK || $!==EINTR;
        warning __x"write to {name} failed: {err}"
          , name => $self->name, err => $!;
        $self->close;
        return
    }

    if($bytes_written==length $$blob)
    {   # we got rit of all at once.  Cheap!
        $more->($self) if $more;
        $self->{IMHW_is_closing}->($self)
            if $self->{IMHW_is_closing};
        return;
    }

    substr($$blob, 0, $bytes_written) = '';
    $self->{IMHW_outbuf} = $blob;
    $self->{IMHW_more} = $more;
    $self->fdset(1, 0, 1, 0);
}


#-------------------------

sub mux_init($)
{   my ($self, $mux) = @_;
    $self->SUPER::mux_init($mux);
    $self->fdset(1, 0, 1, 0);
}

sub mux_write_flagged()
{   my $self   = shift;
    my $outbuf = $self->{IMHW_outbuf};
    unless($outbuf)
    {   $outbuf = $self->{IMHW_outbuf} = $self->mux_outbuffer_empty;
        unless(defined $outbuf)
        {   # nothing can be produced on call, so we don't need the
            # empty-write signals on the moment (enabled at next write)
            $self->fdset(0, 0, 1, 0);
            return;
        }
        unless(length $$outbuf)
        {   # retry at next interval
            delete $self->{IMHW_outbuf};
            return;
        }
    }

    my $bytes_written = syswrite $self->fh, $$outbuf, $self->{IMHW_write_size};
    if(!defined $bytes_written)
    {   # should happen, but we're kind
        return if $! == EWOULDBLOCK || $! == EINTR || $! == EAGAIN;
        warning __x"write to {name} failed: {err}"
          , name => $self->name, err => $!;
        $self->close;
    }
    elsif($bytes_written==length $$outbuf)
         { delete $self->{IMHW_outbuf} }
    else { substr($$outbuf, 0, $bytes_written) = '' }
}


sub mux_outbuffer_empty()
{   my $self = shift;
    my $more = delete $self->{IMHW_more};
    return $more->() if defined $more;

    $self->fdset(0, 0, 1, 0);
    $self->{IMHW_is_closing}->($self)
        if $self->{IMHW_is_closing};
}


sub mux_output_waiting() { exists shift->{IMHW_outbuf} }

# Closing write handlers is a little complex: it should be delayed
# until the write buffer is empty.

sub close(;$)
{   my ($self, $cb) = @_;
    if($self->{IMHW_outbuf})
    {   # delay closing until write buffer is empty
        $self->{IMHW_is_closing} = sub { $self->SUPER::close($cb)};
    }
    else
    {   # can close immediately
        $self->SUPER::close($cb);
    }
}

1;
