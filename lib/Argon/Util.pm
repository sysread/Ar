package Argon::Util;

use v5.12;
use common::sense;
use Coro::AnyEvent;

use parent 'Exporter';
our @EXPORT = qw(
  backoff_timer
  normalize_address
);

sub backoff_timer {
  my $intvl = shift // 0.01;
  my $count = 0;

  sub {
    if ($count > 0) {
      $intvl += log($count) / log(10);
    }

    ++$count;
    Coro::AnyEvent::sleep $intvl;
  };
}

sub normalize_address {
  state $re_localhost = qr/^(localhost)|(127.0.0.1)|(0.0.0.0)(?=:)/;
  my $addr = shift;
  $addr =~ s/$re_localhost/localhost/;
  return $addr;
}

1;
