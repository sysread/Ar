package Argon::Cipher;
# ABSTRACT: Encryption routines used for communication across Argon nodes

use strict;
use warnings;
use Carp qw(croak);
use Path::Tiny qw(path);
use Exporter qw(import);
require Crypt::CBC;

our @EXPORT    = qw(encrypt decrypt);
our @EXPORT_OK = qw(set_key keyfile);

{ my $cipher;

  sub cipher { $cipher || croak 'no cipher set' }

  sub set_key {
    $cipher = Crypt::CBC->new(
      -key => $_[0],
      -cipher => 'Rijndael',
      -salt => 1,
    );

    return 1;
  }
}

sub keyfile { set_key(path($_[0])->slurp_raw) }
sub encrypt { cipher->encrypt_hex($_[0]) }
sub decrypt { cipher->decrypt_hex($_[0]) }

1;

=head1 SYNOPSIS

  use Argon::Cipher; # exports encrypt(), decrypt()

  # Set the global passphrase for communication with the current process
  Argon::Cipher::set_key('my secret passphrase');

  # Set the global passphrase from a file path
  Argon::Cipher::keyfile('/path/to/keyfile');

  my $msg  = encrypt $str_data;
  my $data = decrypt $msg;

=cut
