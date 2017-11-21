package Argon::Pool;
# ABSTRACT: A managed pool of worker processes

use common::sense;

use Moo;
use Coro;
use Coro::Handle qw(unblock);
use AnyEvent::Util qw(fork_call portable_socketpair);
use Try::Catch;
use Argon::Conn;
use Argon::Msg;

has limit    => (is => 'rw');
has pool     => (is => 'rw', default => sub{ Coro::Channel->new });
has stopping => (is => 'rw', default => sub{ 0 });

sub start {
  my $self = shift;
  $self->stopping(0);

  for (1 .. $AnyEvent::Util::MAX_FORKS) {
    $self->add_worker;
  }
}

sub stop {
  my $self = shift;
  $self->stopping(1);
  $self->pool->shutdown;
}

sub process {
  my ($self, $msg) = @_;
  my $reply;

  while (!$self->stopping) {
    my $worker = $self->pool->get or next; # next if worker self-terminated due to task limit
    my ($count, $conn) = @$worker;

    $conn->send($msg);
    $reply = $conn->recv;

    if ($self->{limit} && ++$count >= $self->{limit}) {
      $conn->shutdown;
      $conn->close;
    }
    else {
      $self->pool->put([$count, $conn]);
    }

    last;
  }

  return $reply;
}

sub add_worker {
  my $self = shift;
  my ($child, $parent) = portable_socketpair;

  fork_call {
    close $child;

    while (defined(my $line = <$parent>)) {
      my $msg = Argon::Msg->decode($line);
      my $data = $msg->data;
      my ($code, @args) = @$data;

      try {
        my $result = $code->(@args);
        $msg->reply(cmd => 'done', data => $result);
      }
      catch {
        $msg->reply(cmd => 'fail', data => $_);
      };

      syswrite $parent, $msg->encode . "\n";
    }
  }
  sub {
    close $parent;
    unless ($self->stopping) {
      $self->add_worker;
    }
  };

  close $parent;
  my $conn = Argon::Conn->new(handle => unblock($child));
  $self->pool->put([0, $conn]);
}

1;
