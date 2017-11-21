use Test2::Bundle::Extended;
use Argon::Cipher;

like dies{ encrypt 'foo' }, qr/no cipher set/, 'encrypt fails with no key set';
like dies{ decrypt 'foo' }, qr/no cipher set/, 'decrypt fails with no key set';

ok Argon::Cipher::set_key('testing'), 'set_key';
isnt encrypt('foo'), 'foo', 'encrypt';
is decrypt(encrypt('foo')), 'foo', 'decrypt';

my $secret = encrypt 'foo';
Argon::Cipher::set_key('something else');
isnt decrypt($secret), 'foo', 'incorrect key';

done_testing;
