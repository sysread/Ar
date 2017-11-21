use Test2::Bundle::Extended;
use AnyEvent::Util 'portable_socketpair';
use Coro;
use Coro::Handle 'unblock';
use Argon::Cipher;
use Argon::Conn;
use Argon::Mailbox;
use Argon::Msg;

ok Argon::Cipher::set_key('testing'), 'set_key';

my ($fh_l, $fh_r) = portable_socketpair;
my $left  = Argon::Conn->new(handle => unblock($fh_l));
my $right = Argon::Conn->new(handle => unblock($fh_r));
my $msg   = Argon::Msg->new(cmd => 'pls', data => 'foo');
my $reply = $msg->reply(cmd => 'done', data => 'bar');

$right->send($reply); # get the reply ready

ok my $mail = Argon::Mailbox->new(conn => $left), 'new';
ok my $recv = $mail->get_reply($msg), 'get_reply';
is $recv->id, $reply->id, 'id matches';
is $recv->cmd, $reply->cmd, 'cmd matches';
is $recv->data, $reply->data, 'data matches';

done_testing;
