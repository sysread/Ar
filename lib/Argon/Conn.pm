package Argon::Conn;
# ABSTRACT: A non-blocking connection using L<Argon::Msg>s for communication

use common::sense;

use Moo;
use AnyEvent::Log;
use Argon::Msg;

has handle => (
  is => 'ro',
  required => 1,
  handles => {
    host     => 'peerhost',
    port     => 'peerport',
    close    => 'close',
    shutdown => 'shutdown',
  },
);

sub addr {
  my $self = shift;
  join ':', $self->host, $self->port;
}

sub send {
  my ($self, $msg) = @_;
  $self->handle->print($msg->encode, "\n");
}

sub recv {
  my $self = shift;
  my $line = $self->handle->readline("\n") or return;
  chomp $line;
  Argon::Msg->decode($line);
}

1;
