use Test2::Bundle::Extended;
use AnyEvent::Util 'portable_socketpair';
use Coro::Handle 'unblock';
use Argon::Cipher;
use Argon::Conn;
use Argon::Msg;

Argon::Cipher::set_key('testing');

my ($fh_l, $fh_r) = portable_socketpair;
ok my $left  = Argon::Conn->new(handle => unblock($fh_l)), 'left';
ok my $right = Argon::Conn->new(handle => unblock($fh_r)), 'right';

if ($^O eq 'MSWin32') {
  like $left->addr,  qr/[^:]+:[\d+]/, 'addr';
  like $right->addr, qr/[^:]+:[\d+]/, 'addr';
}
else {
  is $left->addr,  'unix', 'addr';
  is $right->addr, 'unix', 'addr';
}

my $msg = Argon::Msg->new(cmd => 'pls', data => 'how now brown bureaucrat');

ok $left->send($msg), 'send';
ok my $sent = $right->recv, 'recv';
is $sent->id, $msg->id, 'id: received message matches sent message';
is $sent->cmd, $msg->cmd, 'cmd: received message matches sent message';
is $sent->data, $msg->data, 'data: received message matches sent message';

my $reply = $sent->reply(cmd => 'done', data => 'the quick brown fox');
ok $right->send($reply), 'send reply';
ok my $recv = $left->recv, 'receive reply';
is $recv->id, $reply->id, 'id: received message matches sent message';
is $recv->cmd, $reply->cmd, 'cmd: received message matches sent message';
is $recv->data, $reply->data, 'data: received message matches sent message';

ok $left->close, 'close left side';
is $right->recv, U, 'right side recvs undef';
is $right->send($reply), U, 'right send is undef after other end closed';

done_testing;
