package Argon::Server;
# ABSTRACT: A listener socket service

use common::sense;

use Moo;
use Argon::Conn;
use AnyEvent::Log;
use AnyEvent::Socket 'tcp_server';
use Coro::Handle 'unblock';
use Coro;

has port    => (is => 'rw');
has host    => (is => 'rw');
has qsize   => (is => 'ro', default => 256); # listen queue size
has guard   => (is => 'rw', clearer => 1);
has handle  => (is => 'rw', clearer => 1);
has started => (is => 'rw', default => sub{ 0 });
has clients => (is => 'rw', default => sub{ Coro::Channel->new });

sub start {
  my $self = shift;
  $self->clear_guard;
  $self->clear_handle;
  $self->started(1);

  my $guard = tcp_server $self->host, $self->port,
    sub {
      my ($fh, $host, $port) = @_;
      AE::log trace => 'New client connection from %s:%d', $host, $port;
      $self->clients->put(
        Argon::Conn->new(
          handle => unblock($fh),
          host   => $host,
          port   => $port,
        )
      );
    },
    sub {
      my ($fh, $host, $port) = @_;
      $self->host($host);
      $self->port($port);
      $self->handle(unblock $fh);
      AE::log info => 'Listener started on %s:%d', $host, $port;
      return $self->qsize;
    };

  $self->guard($guard);
}

sub stop {
  my $self = shift;
  AE::log debug => 'Shutting down listener';
  $self->clients->shutdown;
  $self->clear_guard;
}

sub client {
  my $self = shift;
  $self->start unless $self->started;
  return $self->clients->get;
}

1;

=head1 SYNOPSIS

  my $service = Argon::Server->new(
    host  => 'localhost',
    port  => 8080, # leave blank for an OS-assigned port
    qsize => 256,  # accept queue size
  );

  $service->start;

  while (my $client = $service->client) {
    $client->send(Argon::Msg->new(cmd => 'fail', data => 'Go away!'));
  }

=head1 DESCRIPTION

Sets up a listener socket on the specified host and port.

=head1 METHODS

=head2 new

=over

=item port

The port on which to listen. Leave blank to request an open port assigned by
the operating system and have the C<port> attribute updated after calling
L</start>.

=item host

The host interface on which to listen. Leave blank to accept the operating
system default and have the C<host> attribute updated after calling L</start>.

=item qsize

Explicitly sets the accept queue length. Leave blank to accept the OS default.
The accept queue holds new connections waiting to be accepted (via a call to
L</client>). If the number of incoming, unanswered, connections grows past the
C<qsize>, new connections will be rejected by the OS.

=back

=head2 stop

Stops the listener service. Any threads waiting on L</client> will be woken up
and receive C<undef>.

=head2 client

Waits for and returns the next incoming client L<connection|Argon::Conn>.

=cut
