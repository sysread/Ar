requires 'perl'                 => '5.012';
requires 'Carp'                 => '0';
requires 'List::Util'           => '0';
requires 'POSIX'                => '0';
requires 'Time::HiRes'          => '0';

requires 'common::sense'        => '0';
requires 'AnyEvent'             => '7.14';
requires 'Coro'                 => '6.514';
requires 'Crypt::CBC'           => '0';
requires 'Crypt::Rijndael'      => '0';
requires 'Data::Dump::Streamer' => '0';
requires 'Data::UUID::MT'       => '0';
requires 'Moo'                  => '0';
requires 'Path::Tiny'           => '0';
requires 'Try::Catch'           => '0';

on test => sub {
  requires 'Test2::Bundle::Extended' => '0';
  requires 'Test::Pod' => '0';
};
