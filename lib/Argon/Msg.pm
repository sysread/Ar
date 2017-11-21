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

has id   => (is => 'ro', default => \&next_id);
has cmd  => (is => 'rw');
has data => (is => 'rw');
has blob => (is => 'rw');

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
