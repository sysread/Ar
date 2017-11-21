package Argon::Pool;
# ABSTRACT: A managed pool of worker processes

use common::sense;

use Moo;
use Coro;
use AnyEvent::Util qw(fork_call portable_socketpair);
use Coro::Handle qw(unblock);
use Try::Catch;
use Argon::Conn;
use Argon::Msg;

has limit    => (is => 'rw');
has pool     => (is => 'rw', default => sub{ Coro::Channel->new }, handles => [qw(size)]);
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

=head1 SYNOPSIS

  my $pool  = Argon::Pool->new(limit => 200);
  my $reply = $pool->process($msg);

  if ($reply->cmd eq 'fail') {
    croak $reply->data;
  }
  else {
    my $result = $reply->data;
  }

  $pool->stop;


=head1 DESCRIPTION

A managed pool of forked worker processes for processing L<Argon::Msg>
tasks.

=head1 METHODS

=head2 new

Expects a single, optional, parameter, C<limit>, which controls the
number of requests a worker process may handle before being restarted.

The number of workers is controlled by the variable
C<$AnyEvent::Util::MAX_FORKS>. See L<AnyEvent::Util/fork_call>.

=head2 process

Accepts an L<Argon::Msg> prepared as a task, assigns it to a worker in the
pool, then awaits and returns the result. A task is an L<Argon::Msg> with the
C<cmd> 'pls', and a value for C<data> structured as an array composed of a code
ref and any arguments to pass to the code ref:

  [CODEREF, $arg, $arg, ...]

=head2 stop

Signals the pool to shut down, preventing new workers from starting and new
tasks from being accepted. Any threads waiting on a task to complete are woken
up, receiving undef instead of a completed reply msg.

=cut
