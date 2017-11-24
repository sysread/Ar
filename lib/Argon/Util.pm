package Argon::Util;

use common::sense;
use Coro::AnyEvent;

use parent 'Exporter';
our @EXPORT = qw(
  backoff_timer
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



1;
