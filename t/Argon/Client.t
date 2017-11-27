use Test2::Bundle::Extended;
use Coro;
use Coro::AnyEvent qw();
use Argon::Cipher;
use Argon::Client;
use Argon::Hub;
use Argon::Node;
use Argon::Msg;

Argon::Cipher::set_key('testing');

sub timed {
  my ($timeout, $code) = @_;
  my $check = async{ $code->() };
  my $timer = async{
    Coro::AnyEvent::sleep $timeout;
    $check->throw('timeout');
  };
  $check->join;
  $timer->safe_cancel;
}

# Launch a hub to accept our test client's connection
my $hub = Argon::Hub->new;
$hub->start;
my $h = async{$hub->run};

# Start a node to perform the hub's tasks
my $node = Argon::Node->new(host => $hub->host, port => $hub->port);
my $n = async{$node->run};

# Test client
ok my $client = Argon::Client->new(host => $hub->host, port => $hub->port), 'new';
is $client->addr, join(':', $hub->host, $hub->port), 'addr';

timed(10, sub{
  ok $client->connect, 'connected';
  ok $client->ping, 'ping';
  ok $client->latency(10), 'latency';
});

timed(20, sub{
  my @pending = map{ async{ $client->task(sub{ shift() * 2 }, shift()) } $_ } 1 .. 10;
  is [map{ $_->join } @pending], [map{ $_ * 2 } 1 .. 10], 'expected results in order';
});

$client->close;
$node->stop;
$hub->stop;

done_testing;
