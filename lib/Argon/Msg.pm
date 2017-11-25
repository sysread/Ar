package Argon::Msg;
# ABSTRACT: A unit of communication between Argon nodes

use common::sense;
use v5.12;

use Moo;
use Carp;
use Coro;
use Coro::Timer;
use Data::Dump::Streamer qw(Dump);
use Data::UUID::MT;
use MIME::Base64 qw(encode_base64 decode_base64);
use Try::Catch;
use Argon::Cipher;

extends 'Exporter';
our @EXPORT = qw(msg);

has id   => (is => 'ro', default => \&next_id);
has cmd  => (is => 'rw');
has data => (is => 'rw');
has blob => (is => 'rw');

sub msg { Argon::Msg->new(@_) }

sub reply {
  my ($self, %update) = @_;
  $self->$_($update{$_}) foreach keys %update;
  return $self;
}

sub encode {
  my $self = shift;
  my $line = join ' ', $self->cmd, $self->id, $self->blob // freeze($self->{data});
  encrypt($line);
}

sub decode {
  my ($class, $line) = @_;
  my ($cmd, $id, $blob) = split / /, decrypt($line), 3;
  Argon::Msg->new(id => $id, cmd => $cmd, blob => $blob);
}

around data => sub {
  my $orig = shift;
  my $self = shift;

  # 1) not a setter
  # 2) data slot is empty
  # 3) blob is set
  if (@_ == 0 && !defined($self->{data}) && $self->blob) {
    $self->{data} = thaw($self->blob);
  }
  # Setter updates the blob
  elsif (@_ > 0) {
    my $data = $_[0];              # Value must have a local ref to be stored correctly
    $self->{blob} = freeze($data); # Update the blob to the frozen data value
    undef $self->{data};           # Undef data so future accessor calls know to thaw the blob
    return $_[0];                  # Short-circuit before calling $orig, which would set $self->{data}
  }

  $self->$orig(@_);
};

sub next_id {
  state $gen = Data::UUID::MT->new;
  $gen->create_string;
}

sub freeze  {
  encode_base64(marshal($_[0], ''));
}

sub marshal {
  state $dumper = Dump->Purity(1)->Declare(1)->Indent(0)->RLE(1);
  $dumper->Data($_[0])->Out;
}

sub thaw {
  my $data = decode_base64($_[0]);
  my $ref  = eval "do{$data}";
  $@ && croak "decode error: $@";
  $ref;
}

1;

=head1 SYNOPSIS

  use Argon::Msg;

  my $msg = Argon::Msg->new(
    cmd  => 'done',
    data => {some => 'data'},
  );

  my $line = $msg->encode;

  my $decoded = Argon::Msg->decode($line);

=head1 DESCRIPTION

This class encodes and decodes the line protocol used for communication between
L<Argon> nodes.

=head1 METHODS

=head2 new

=over

=item id

A unique identifier for this message. Unless specified, a new UUID is provided
automatically. An id should only be reused when replying to a message. See
L</reply>.

=item cmd

A command verb (hopefully one that is expected by whatever is listening on the
other end of the line).

=item data

A scalar value or reference to be serialized and transmitted as the payload of
this message.

=back

=head2 encode

Serializes and encrypts the message into a single line suitable for
transmission to another Argon entity.

  $conn->send($msg->encode);

=head2 decode

Decodes an encrypted line (provided by L</encode> or read off the wire) and
returns a new C<Argon::Msg> instance. This is a class method.

  my $msg = Argon::Msg->decode(<STDIN>);

=head2 reply

Updates any number of instance attributes in place and returns the updated
object.

  my $reply = $msg->reply(cmd => 'fail', data => 'some error message');

=cut
