package Argon::Node;
# ABSTRACT: A worker node in an Argon network

use common::sense;

use Moo;
use AnyEvent::Log;
use AnyEvent::Util qw();
use Carp;
use Coro;
use Coro::AnyEvent;
use Ion;

use Argon::Msg;
use Argon::Pool;
use Argon::Util;

# Process pool
has limit => (is => 'rw');
has pool  => (is => 'rw', clearer => 1);

# Manager connection
has port  => (is => 'ro', required => 1);
has host  => (is => 'ro', required => 1);
has conn  => (is => 'rw', clearer  => 1);

# State
has stopped => (is => 'rw', default => sub{ 1 });

sub run {
  my $self = shift;
  $self->stopped(0);

  AE::log info => 'Node is starting';
  AE::log info => 'Process limit: %d', $AnyEvent::Util::MAX_FORKS;
  AE::log info => 'Max requests: %s', $self->limit // '-';

  # Launch process pool
  $self->pool(Argon::Pool->new(limit => $self->limit));
  $self->pool->start;

  my $timer;
  until ($self->stopped) {
    # Connect to hub if necessary
    unless ($self->conn) {
      if ($self->conn($self->connect)) {
        AE::log info => 'Connected to hub';
        undef $timer;
      }
      else {
        # Connection failed
        $self->clear_conn;
        $timer //= backoff_timer;
        $timer->();
        next;
      }
    }

    my $msg = $self->recv
      or next;

    # Send to pool and add callback to return the result
    async_pool {
      my ($self, $msg) = @_;
      my $reply = $self->pool->process($msg);
      # Connection might have been lost before callback is called
      $self->conn->($reply->encode) if $self->conn;
    } $self, $msg;
  }
}

sub stop {
  my $self = shift;
  $self->stopped(1);
  AE::log info => 'Node is stopping';

  # Wait until all tasks are complete
  $self->pool->stop;

  # Close connection to the hub
  $self->conn->(0) if $self->conn;

  # Clean up
  $self->clear_pool;
  $self->clear_conn;
}

sub connect {
  my $self = shift;
  AE::log debug => 'Establishing connection to hub';
  $self->clear_conn;

  my $conn = eval{ Connect $self->host, $self->port };

  if ($@) {
    AE::log debug => $@;
    return;
  }

  $conn->(msg(cmd => 'reg', data => $AnyEvent::Util::MAX_FORKS)->encode);
  my $reply = <$conn>; # ack
  return $conn;
}

sub recv {
  my $self = shift;

  # Retrieve next message from hub
  my $conn = $self->conn;
  my $line = <$conn>;

  # Disconnected
  unless (defined $line) {
    $self->clear_conn;
    return;
  }

  return Argon::Msg->decode($line);
}

1;
