package Argon::Node;
# ABSTRACT: A worker node in an Argon network

use common::sense;

use Moo;
use AnyEvent::Log;
use AnyEvent::Util qw();
use Argon::Pool;
use Carp;
use Coro;
use Coro::AnyEvent;
use Try::Catch;

use Argon::Client;
use Argon::Msg;
use Argon::Util;

# Process pool
has limit   => (is => 'rw');
has pool    => (is => 'rw', clearer => 1);

# Manager connection
has port    => (is => 'ro', required => 1);
has host    => (is => 'ro', required => 1);
has client  => (is => 'rw', clearer  => 1, handles => [qw(send recv)]);

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
    unless ($self->client) {
      if ($self->client($self->connect)) {
        AE::log info => 'Connected to hub';
        undef $timer;
      }
      else {
        # Connection failed
        $self->clear_client;
        $timer //= backoff_timer;
        $timer->();
        next;
      }
    }

    # Retrieve next message from hub
    my $msg = $self->recv;

    # Hub was disconnected
    unless ($msg) {
      $self->clear_client;
      next;
    }

    # Send to pool and add callback to return the result
    async_pool {
      my ($self, $msg) = @_;
      my $reply = $self->pool->process($msg);
      # Client might have disconnected before callback is called
      $self->send($reply) if $self->client;
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
  $self->client->close if $self->client;

  # Clean up
  $self->clear_pool;
  $self->clear_client;
}

sub connect {
  my $self = shift;
  AE::log debug => 'Establishing connection to hub';
  $self->clear_client;

  # Connect to hub
  my $client = Argon::Client->new(host => $self->host, port => $self->port);
  $client->connect
    or return;

  # Register capacity with hub
  $client->send(Argon::Msg->new(cmd => 'reg', data => $AnyEvent::Util::MAX_FORKS));

  # Wait for acknowledgement
  my $reply = $client->recv
    or return;

  if ($reply->cmd ne 'ack') {
    AE::log warn => 'server replied with %s: %s', $reply->cmd, $reply->data;
    return;
  }

  return $client;
}

1;
