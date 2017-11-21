package Argon::Hub::Node;
# ABSTRACT: A managed connection from a remote note

use Moo;
use Argon::Mailbox;

has conn => (is => 'ro', required => 1);
has cap  => (is => 'ro', required => 1);

has mail => (
  is       => 'ro',
  required => 1,
  handles  => {
    join     => 'join',
    shutdown => 'shutdown',
    process  => 'get_reply',
    send     => 'send',
    recv     => 'recv',
    pending  => 'num_pending',
  }
);

sub BUILDARGS {
  my ($class, %param) = @_;
  $param{mail} = Argon::Mailbox->new(conn => $param{conn});
  return \%param;
}

sub load {
  my $self = shift;
  my $load = $self->pending or return 0;
  return $self->cap / $load;
}

1;


package Argon::Hub;
# ABSTRACT: Handles incoming client tasks using a pool of Argon::Node workers

#-------------------------------------------------------------------------------
# TODO
#   - when node disconnects, retain pending messages for a set period of time
#     to allow the node a chance to reconnect
#       - Argon::Msg expire time
#       - Default to configurable value
#       - Configurable cap on max value
#   - monitor node ping
#-------------------------------------------------------------------------------

use common::sense;

use Moo;
use AnyEvent::Log;
use Argon::Msg;
use Argon::Server;
use Coro;
use List::Util qw(reduce sum0 min);
use Time::HiRes qw(time);

extends 'Argon::Server';

has backlog  => (is => 'ro', default => sub{ 30 }); # seconds of backlog to allow (est)
has capacity => (is => 'rw', default => sub{ 0 });  # tracks total worker processes across registered nodes
has load     => (is => 'rw', default => sub{ 0 });  # tracks number of pending tasks (assigned but not complete)
has nodes    => (is => 'rw', default => sub{ {} }); # addr -> Argon::Hub::Node
has average  => (is => 'rw', default => sub{ 0 });  # rolling average of task processing times
has history  => (is => 'rw', default => sub{ [] }); # historical times of tasks processed

# Initialize the hub
after start => sub {
  my $self = shift;

  # New client connection
  while (my $client = $self->client) {
    # Start client observer thread to service client requests
    async_pool(\&client_observer, $self, $client);
  }
};

sub add_capacity {
  my ($self, $amount) = @_;
  $self->capacity($self->capacity + $amount);
  AE::log info => 'Capacity increased to %d', $self->capacity;
}

sub remove_capacity {
  my ($self, $amount) = @_;
  $self->capacity($self->capacity - $amount);
  AE::log info => 'Capacity decreased to %d', $self->capacity;
}

sub inc_load { ++$_[0]->{load} }
sub dec_load { --$_[0]->{load} }

sub client_observer {
  my ($self, $client) = @_;

  while (my $msg = $client->recv) {
    AE::log trace => 'Received message %s: %s', $msg->cmd, $msg->id;
    # Client: pls do this task?!
    if ($msg->cmd eq 'pls') {
      async_pool {
        my ($self, $client, $msg) = @_;
        # Process returns undef when a node disconnects before the task can be
        # sent. Loop until some node sends a reply.
        my $reply; do{ $reply = $self->process($msg) } until $reply;
        $client->send($reply);
      } $self, $client, $msg;
    }
    # Node registration
    elsif ($msg->cmd eq 'reg') {
      # Start an observer thread to register the node and monitor for
      # task results.
      async_pool(\&node_observer, $self, $client, $msg);

      # Because this was not a client but a node, this thread is no longer
      # necessary or appropriate.
      last;
    }
  }
}

sub process {
  my ($self, $msg) = @_;
  if ($self->has_capacity && (my $node = $self->select_node)) {
    return $self->tracked(sub{ $self->nodes->{$node}->process($msg) });
  }
  # No capacity to service requests
  else {
    AE::log trace => '%s: no capacity', $msg->id;
    return $msg->reply(cmd => 'fail', data => 'no available capacity');
  }
}

# Supervisor for node connection. Registers the node's capacity and cleans up
# if it disconnects.
sub node_observer {
  my ($self, $conn, $reg) = @_;
  my $addr = $conn->addr;

  # Start a mailbox for the node to track messages in and out
  my $node = Argon::Hub::Node->new(
    conn => $conn,
    cap  => $reg->data,
  );

  $self->nodes->{$addr} = $node;   # Stow the node
  $self->add_capacity($node->cap); # Add node's capacity to our own
  $reg->cmd('ack');                # Reply with acknowledgement
  $node->send($reg);

  # Wait until the mailbox signals that it has exited
  $self->nodes->{$addr}->join;

  # Node has disconnected; remove its capacity
  AE::log info => 'Worker disconnected: %s', $addr;
  $self->remove_capacity($node->cap);
  $node->shutdown;
  delete $self->nodes->{$addr};
}

sub select_node {
  my $self = shift;
  reduce{ $self->nodes->{$a}->load < $self->nodes->{$b}->load ? $a : $b }
    keys %{$self->nodes};
}

sub has_capacity {
  my $self = shift;
  return 1 if $self->load < $self->capacity;
  return ($self->average * ($self->load - $self->capacity)) <= $self->backlog;
}

sub tracked {
  my ($self, $work) = @_;
  $self->inc_load;                                              # track increase in number of tasks pending
  my $start = time;                                             # note start time
  my $result = $work->();                                       # do the work
  push @{ $self->history }, time - $start;                      # add time taken to history
  shift @{$self->history} while scalar @{$self->history} > 200; # prune history
  my $avg = sum0(@{$self->history})/scalar(@{$self->history});  # calculate new avg processing time
  $self->average($avg);                                         # update average task processing time
  $self->dec_load;                                              # note decrease in number of tasks pending
  $result;
}

1;