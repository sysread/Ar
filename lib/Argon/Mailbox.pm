package Argon::Mailbox;
# ABSTRACT: Links replies with the watcher expecting them

use common::sense;
use Time::HiRes qw(time);
use AnyEvent::Log;
use Coro;
use Moo;

has conn    => (is => 'ro', handles => [qw(addr)]),
has reader  => (is => 'rw');
has writer  => (is => 'rw');
has inbox   => (is => 'ro', default => sub{ Coro::Channel->new }, handles => {recv => 'get'});
has outbox  => (is => 'ro', default => sub{ Coro::Channel->new }, handles => {send => 'put'});
has pending => (is => 'ro', default => sub{ {} });
has active  => (is => 'rw', default => sub{ 0 });

sub BUILD {
  my $self = shift;
  $self->reader(async(\&reader_loop, $self));
  $self->writer(async(\&writer_loop, $self));
  $self->active(1);
}

sub shutdown {
  my $self = shift;
  $self->active(0);
  $self->inbox->shutdown;
  $self->outbox->shutdown;

  # Rouse watchers and disappoint them
  foreach my $msg_id (keys %{$self->pending}) {
    my $cb = delete $self->pending->{$msg_id};
    my $msg = Argon::Msg->new(
      id   => $msg_id,
      cmd  => 'fail',
      data => 'message was sent but recipient disconnected before replying',
    );
    $cb->($msg);
  }
}

sub join {
  my $self = shift;
  $self->reader->join;
  $self->writer->join;
}

# Send a message, then cede until its reply (with a matching id) is received.
sub get_reply {
  my ($self, $msg) = @_;
  $self->pending->{$msg->id} = rouse_cb;
  $self->send($msg);
  rouse_wait($self->pending->{$msg->id});
}

sub num_pending {
  my $self = shift;
  scalar keys %{$self->pending};
}

sub reader_loop {
  my $self = shift;

  while ($self->active) {
    if (my $msg = $self->conn->recv) {
      AE::log trace => 'recv msg %s: %s', $msg->cmd, $msg->id;

      # Message has watchers - rouse them
      if (exists $self->pending->{$msg->id}) {
        my $cb = delete $self->pending->{$msg->id};
        $cb->($msg);
      }
      # Message has no watchers - post to inbox
      else {
        $self->inbox->put($msg);
      }
    }
    # Disconnected
    else {
      $self->shutdown;
      last;
    }
  }
}

sub writer_loop {
  my $self = shift;

  while ($self->active) {
    my $msg = $self->outbox->get
      or last;

    if ($self->active) {
      $self->conn->send($msg);
      AE::log trace => 'send msg %s: %s', $msg->cmd, $msg->id;
    }
  }
}

1;
