package Argon::Client;

use common::sense;

use Carp;
use Coro;
use Ion;
use Argon::Msg qw(msg);
use Argon::Util qw(backoff_timer);

use parent 'Exporter';
our @EXPORT_OK = qw(mailbox client);

sub mailbox {
  my ($host, $port) = @_;
  my $conn = Connect $host, $port;
  my ($closed, %pending);

  async_pool {
    while (my $line = <$conn>) {
      my $msg = Argon::Msg->decode($line);
      my $cb = delete $pending{$msg->id};
      $cb->($msg) if $cb;
    }

    $closed = 1;
  };

  return sub {
    croak 'disconnected' if $closed;
    my $msg = shift;

    unless ($msg) {
      $conn->close;
      $closed = 1;
      return;
    }

    $pending{$msg->id} = rouse_cb;
    $conn->($msg->encode);
    return rouse_wait;
  };
}

sub client {
  my ($host, $port, $retries) = @_;
  my $mailbox = mailbox shift, shift;
  my $retries = shift // 10;

  return sub {
    my $msg = msg(cmd => 'pls', data => [@_]);
    my $tries = $retries;
    my $timer;

    RETRY:
    croak 'no available capacity' if $tries-- == 0;
    my $reply = $mailbox->($msg);

    if ($reply->cmd eq 'fail') {
      croak $reply->data unless $reply->data eq 'no available capacity';
      $timer //= backoff_timer;
      $timer->();
      goto RETRY;
    }
    else {
      return $reply->data;
    }
  };
}

1;
