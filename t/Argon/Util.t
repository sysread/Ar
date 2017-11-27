use Test2::Bundle::Extended;
use Argon::Util;

subtest backoff_interval => sub {
  ok my $t = backoff_interval, 'backoff_interval';
  is ref $t, 'CODE', 'code ref';

  my $acc = 1;
  for (1 .. 10) {
    my $check = $acc + log($_) / log(10);
    $acc = $t->();
    is $acc, $check, "interval $_: expected value";
  }
};

done_testing;
