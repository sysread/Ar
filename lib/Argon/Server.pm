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
