package TestServer;
use Moo;
with 'Argon::Server';
1;


package main;
use Test2::Bundle::Extended;
use Coro;
use Coro::AnyEvent qw();
use Argon::Cipher;
use Argon::Conn;
use Argon::Msg;

Argon::Cipher::set_key('testing');

my $msg = Argon::Msg->new(cmd => 'test', data => {foo => 'bar'});

ok my $s = TestServer->new, 'new';

$s->start;

ok $s->port, 'port assigned';
ok $s->host, 'host assigned';
ok $s->addr, 'addr set';

my $server = async {
  ok my $conn = $s->next_connection, 'next_connection';
  ok my $recv = $conn->recv, 'msg received';
  return $recv;
};

my $client = async {
  ok my $conn = Argon::Conn->open($s->host, $s->port), 'connect to server';
  ok $conn->send($msg), 'send message to server';
  $conn->shutdown;
  $conn->close;
  return 1;
};

my $timer = async {
  Coro::AnyEvent::sleep 10;
  $client->throw('timeout');
};

my $recv = $server->join;
$timer->safe_cancel;

is $recv->id, $msg->id, 'send/recv msg id';
is $recv->cmd, $msg->cmd, 'send/recv msg cmd';
is $recv->data, $msg->data, 'send/recv msg data';

$s->stop;

is $s->next_connection, U, 'next_connection undefined after stop is called';

done_testing;
