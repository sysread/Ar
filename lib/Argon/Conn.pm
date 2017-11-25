package Argon::Conn;
# ABSTRACT: A non-blocking connection using L<Argon::Msg>s for communication

use common::sense;

use Moo;
use Coro;
use Coro::Handle 'unblock';
use AnyEvent::Log;
use AnyEvent::Socket 'tcp_connect';
use Argon::Msg;

has handle => (
  is       => 'ro',
  required => 1,
  clearer  => 1,
  handles  => {
    host     => 'peerhost',
    port     => 'peerport',
    close    => 'close',
    shutdown => 'shutdown',
  },
);

sub is_connected { defined $_[0]->handle }

sub open {
  my ($class, $host, $port) = @_;
  AE::log debug => 'Connecting to %s:%d', $host, $port;
  my $guard = tcp_connect($host, $port, rouse_cb);
  my ($fh)  = rouse_wait or return;
  return $class->new(handle => unblock($fh));
}

sub addr {
  my $self = shift;
  $self->host eq 'unix/' ? 'unix' : join(':', $self->host, $self->port);
}

sub send {
  my ($self, $msg) = @_;
  $self->handle->print($msg->encode, "\n");
}

sub recv {
  my $self = shift;
  my $line = $self->handle->readline("\n");

  unless ($line) {
    $self->clear_handle;
    return;
  }

  chomp $line;
  Argon::Msg->decode($line);
}

1;

=head1 SYNOPSIS

  use Argon::Conn;
  use Argon::Msg;

  my $conn = Argon::Conn->new(handle => $coro_handle);

  $conn->send(Argon::Msg->new(...));

  my $reply = $conn->recv;

  $conn->shutdown;
  $conn->close;

=head1 METHODS

=head2 send

Encodes and sends an L<Argon::Msg> on the socket.

=head2 recv

Reads and returns the next L<Argon::Msg> from the socket.

=head2 host

Returns the remote host (C<peerhost>);

=head2 port

Returns the remote port (C<peerport>);

=head2 addr

Returns the remote address in the form, C<host:port>.

=head2 close

Close the socket.

=head2 shutdown

Shuts down the socket, signaling the other end that no more data will be sent.

=cut
