use Test2::Bundle::Extended;
use AnyEvent::Util;
use Argon::Pool;
use Argon::Msg;

$AnyEvent::Util::MAX_FORKS = 1;

Argon::Cipher::set_key('testing');

ok my $pool = Argon::Pool->new(limit => 1), 'new';
is $pool->size, 0, 'no workers started initially';

$pool->start;
is $pool->size, $AnyEvent::Util::MAX_FORKS, 'expected number of workers started';

my $task = Argon::Msg->new(cmd => 'pls', data => [sub{shift() * 2}, 21]);
ok my $reply = $pool->process($task), 'process';
is $reply->cmd, 'done', 'cmd';
is $reply->data, 42, 'data';

$pool->stop;

done_testing;
