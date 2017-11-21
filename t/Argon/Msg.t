use Test2::Bundle::Extended;
use Argon::Msg;
use Argon::Cipher;

Argon::Cipher::set_key('testing');

isnt Argon::Msg::next_id, Argon::Msg::next_id, 'next_id';

subtest 'basics' => sub{
  # Creation
  ok my $msg = Argon::Msg->new(cmd => 'ack', data => 'asdf'), 'msg';
  ok $msg->id, 'default id';

  # Encoding/decoding
  ok my $line = $msg->encode, 'encode';
  ok my $msg2 = Argon::Msg->decode($line), 'decode';
  is $msg2->id, $msg->id, 'encode <-> decode: id';
  is $msg2->cmd, $msg->cmd, 'encode <-> decode: cmd';

  # Lazy data decoding
  ok $msg2->blob, 'blob is set';
  is $msg2->{data}, U, 'data not set by decode';
  ok $msg2->data, 'accessor sets data';
  is $msg2->data, 'asdf', 'encode <-> decode: data';
  ok my $blob = $msg2->blob, 'blob retained';

  $msg2->data('foo');

  is $msg2->{data}, U, 'data undef after setter is called';
  isnt $msg2->blob, $blob, 'blob updated when data is set';
  is $msg2->data, 'foo', 'data updated from new blob';
};

done_testing;
