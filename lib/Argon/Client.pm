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
has addr    => (is => 'rw');
has conn    => (is => 'rw', clearer => 1, handles => [qw(is_connected)]);
has mailbox => (is => 'rw', clearer => 1, handles => [qw(send recv get_reply)]);

before [qw(get_reply send recv latency)]
  => sub{ croak 'not connected' unless $_[0]->is_connected };

sub connect {
  my $self = shift;
  my $conn = Argon::Conn->open($self->host, $self->port);

  unless ($conn) {
    AE::log info => 'Connection failed: %s', $!;
    return;
  }

  $self->addr(join ':', $self->host, $self->port);
  $self->conn($conn);
  $self->mailbox(Argon::Mailbox->new(conn => $self->conn));

  AE::log debug => 'Connection established';
  return 1;
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
  my $self = shift;
  my $msg  = Argon::Msg->new(cmd => 'pls', data => [@_]);
  my $timer;

  RETRY:
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
