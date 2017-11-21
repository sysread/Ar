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
use Coro::AnyEvent;
use Coro::Handle 'unblock';
use AnyEvent::Socket 'tcp_connect';
use AnyEvent::Log;
use List::Util 'sum0';
use POSIX 'round';
use Time::HiRes qw(time sleep);
use Try::Catch;
use Argon::Conn;
use Argon::Mailbox;

has host    => (is => 'ro', required => 1);
has port    => (is => 'ro', required => 1);
has addr    => (is => 'rw');
has guard   => (is => 'rw', clearer => 1);
has conn    => (is => 'rw', clearer => 1);
has mailbox => (is => 'rw', clearer => 1, handles => [qw(send recv get_reply)]);

before [qw(get_reply send recv latency)]
  => sub{ croak 'not connected' unless $_[0]->connected };

sub connected {
  my $self = shift;
  return defined $self->guard;
}

sub connect {
  my $self = shift;
  AE::log debug => 'Connecting to %s:%d', $self->host, $self->port;

  my $guard = tcp_connect($self->host, $self->port, rouse_cb);
  my ($fh)  = rouse_wait;

  unless ($fh) {
    AE::log info => 'Connection failed: %s', $!;
    return;
  }

  $self->guard($guard);
  $self->addr(join ':', $self->host, $self->port);
  $self->conn(Argon::Conn->new(handle => unblock($fh)));
  $self->mailbox(Argon::Mailbox->new(conn => $self->conn));

  AE::log debug => 'Connection established';
  return 1;
}

sub close {
  my $self = shift;
  return unless $self->connected;

  $self->mailbox->shutdown;

  try {
    $self->conn->shutdown if $self->conn;
  }
  catch {
    # Not a problem if this fails - it likely means the handle is already closed
  };

  $self->clear_guard;
  $self->clear_conn;
  $self->clear_mailbox;
  AE::log debug => 'Connection closed';
}

sub backoff_timer {
  my $count = 0;
  my $intvl = 0.01;

  sub {
    if ($count == 0) {
      ++$count;
      return $intvl;
    }

    $intvl += log($count++) / log(10);
  };
}

sub task {
  my $self = shift;
  my $msg  = Argon::Msg->new(cmd => 'pls', data => [@_]);
  my $timer;

  RETRY:
  my $reply = $self->get_reply($msg);
  if ($reply->cmd eq 'fail') {
    if ($reply->data eq 'no available capacity') {
      $timer //= backoff_timer;
      Coro::AnyEvent::sleep $timer->();
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
