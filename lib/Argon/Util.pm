package Argon::Util;
# ABSTRACT: Utility functions shared by Argon modules

use common::sense;

use Coro;
use Coro::AnyEvent;

use parent 'Exporter';

our @EXPORT = qw(
  timeout
  backoff_interval
  backoff_timer
);

sub timeout {
  my ($timeout, $code) = @_;
  my $check = async{ $code->() };
  my $timer = async{
    Coro::AnyEvent::sleep $timeout;
    $check->throw('timeout');
  };
  my $result = $check->join;
  $timer->safe_cancel;
  return $result;
}

sub backoff_interval {
  my $intvl = shift // 1;
  my $count = 0;

  sub{
    $intvl += log(++$count) / log(10);
    $intvl;
  };
}

sub backoff_timer {
  my $intvl = backoff_interval(@_);
  sub{ Coro::AnyEvent::sleep $intvl->() };
}

1;

=head1 EXPORTED SUBROUTINES

=head2 backoff_interval

Creates a logarithmic (log10) backoff function which increments the initial
value (defaulting to 1) by the number of times the returned function is called.

  use Coro::AnyEvent;

  my $intvl = backoff_interval(1);

  while (some_condition_is_true()) {
    Coro::AnyEvent::sleep $intvl->();
  }

=head2 backoff_timer

Returns a function which L<sleeps|Coro::AnyEvent/sleep> for a logarithmically
increasing number of seconds. All arguments are passed unchanged to
L</backoff_interval>.

  my $sleep = backoff_timer(3);

  while (some_condition_is_true()) {
    $sleep->();
  }
