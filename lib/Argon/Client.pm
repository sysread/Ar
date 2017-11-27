package Argon::Client;
# ABSTRACT: A connection to an Argon::Hub

#-------------------------------------------------------------------------------
# TODO
#   - Stuff
#-------------------------------------------------------------------------------

use common::sense;

use Moo;
use Carp;
use Coro;
use AnyEvent::Log;
use List::Util 'sum0';
use POSIX 'round';
use Time::HiRes qw(time);
use Try::Catch;
use Argon::Conn;
use Argon::Mailbox;
use Argon::Util;

has host    => (is => 'ro', required => 1);
has port    => (is => 'ro', required => 1);
has retries => (is => 'ro', default => 10);
has addr    => (is => 'rw');
has conn    => (is => 'rw', clearer => 1);
has mailbox => (is => 'rw', clearer => 1, handles => [qw(send recv get_reply)]);

sub BUILD {
  my $self = shift;
  $self->addr(join ':', $self->host, $self->port);
}

before [qw(get_reply send recv latency)]
  => sub{ croak 'not connected' unless $_[0]->is_connected };

sub is_connected { defined $_[0]->conn && $_[0]->conn->is_connected }

sub connect {
  my $self = shift;

  if (!(ref $self) && @_) {
    $self = $self->new(host => shift, port => shift);
  }

  my $conn = Argon::Conn->open($self->host, $self->port);

  unless ($conn) {
    AE::log info => 'Connection failed: %s', $!;
    return;
  }

  $self->conn($conn);
  $self->mailbox(Argon::Mailbox->new(conn => $self->conn));

  AE::log debug => 'Connection established';
  return $self;
}

sub close {
  my $self = shift;
  return unless $self->is_connected;

  $self->mailbox->shutdown;

  try {
    $self->conn->shutdown if $self->conn;
  }
  catch {
    # Not a problem if this fails - it likely means the handle is already closed
  };

  $self->clear_conn;
  $self->clear_mailbox;
  AE::log debug => 'Connection closed';
}

sub task {
  my $self  = shift;
  my $msg   = Argon::Msg->new(cmd => 'pls', data => [@_]);
  my $tries = $self->retries;
  my $timer;

  RETRY:
  croak 'no available capacity' if $tries-- == 0;
  my $reply = $self->get_reply($msg);
  if ($reply->cmd eq 'fail') {
    if ($reply->data eq 'no available capacity') {
      $timer //= backoff_timer;
      $timer->();
      goto RETRY;
    }
    else {
      croak $reply->data;
    }
  } else {
    return $reply->data;
  }
}

# Times travel time for a task in ms
sub ping {
  my $start = time;
  $_[0]->task(sub{});
  my $taken = time - $start;
  round(1000 * $taken);
}

# Average ping time for a single client
sub latency {
  my $self  = shift;
  my $count = shift // 1;

  $self->ping; # ensure handler for our connection is already warmed up

  my @results;
  for (1 .. $count) {
    push @results, $self->ping;
  }

  round(sum0(@results) / scalar(@results));
}

1;

=head1 SYNOPSIS

  use Argon::Client;
  use Coro;

  # Connect to Argon::Hub
  my $client = Argon::Client->connect('some.hostname', 4444)
    or die 'could not connect';

  # Check task latency
  my $ms  = $client->ping;
  my $avg = $client->latency($ping_count);

  # Call and wait
  my $result = $client->task(\&do_stuff, $arg1, $arg2, ...);

  # Run in a thread and join
  my $pending = async{ $client->task(\&do_stuff, @_) } $arg1, $arg2, ...;
  my $result  = $pending->join;

  $client->close;

=head1 METHODS

=head2 new

=over

=item host

Host name of L<Argon::Hub> to connect to.

=item port

Port number of L<Argon::Hub> to connect to.

=item retries

Maximum number of times a task will be retried if the network is over capacity.
Defaults to 10.

=back

=head2 connect

If called as an instance method, connects to the L<Argon::Hub> specified by the
host and port attributes passed to the constructor. If called as an class
method with a host name and port number, builds a new C<Argon::Client> and
connects it. This method cedes until the connection is established.

=head2 close

Disconnects from the remote host.

=head2 task

Requests that the connected L<Argon::Hub> schedule the execution of the
supplied code ref and arguments. Cedes until the result is available and
returns the result. If an error is thrown during execution of the task,
is is re-thrown in the client.

If the network is over capacity, the task will be retried up to C<retry> times.

=head2 ping

Returns the number of milliseconds it takes for a task to make the round trip
from the client to a worker node and back.

=head2 latency

Returns the average L</ping> time across the specified number of pings. Pings
are executed serially and the result of each is waited in turn in order to get
a correct measurement (running them concurrently could put the network over
capacity, resulting in highly skewed numbers).

=cut
