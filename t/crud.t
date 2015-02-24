#
#  Copyright 2015 MongoDB, Inc.
#
#  Licensed under the Apache License, Version 2.0 (the "License");
#  you may not use this file except in compliance with the License.
#  You may obtain a copy of the License at
#
#  http://www.apache.org/licenses/LICENSE-2.0
#
#  Unless required by applicable law or agreed to in writing, software
#  distributed under the License is distributed on an "AS IS" BASIS,
#  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#  See the License for the specific language governing permissions and
#  limitations under the License.
#

use strict;
use warnings;
use Test::More 0.96;
use Test::Fatal;
use Test::Warn;
use Test::Deep qw/!blessed/;

use utf8;
use Tie::IxHash;

use MongoDB;
use MongoDB::Error;

use lib "t/lib";
use MongoDBTest qw/build_client get_test_db server_version server_type/;

my $conn           = build_client();
my $testdb         = get_test_db($conn);
my $server_version = server_version($conn);
my $server_type    = server_type($conn);
my $coll           = $testdb->get_collection('test_collection');

my $res;

subtest "insert_one" => sub {

    # insert doc with _id
    $coll->drop;
    $res = $coll->insert_one( { _id => "foo", value => "bar" } );
    cmp_deeply(
        [ $coll->find( {} )->all ],
        bag( { _id => "foo", value => "bar" } ),
        "insert with _id: doc inserted"
    );
    ok( $res->acknowledged, "result acknowledged" );
    isa_ok( $res, "MongoDB::InsertOneResult", "result" );
    is( $res->inserted_id, "foo", "res->inserted_id" );

    # insert doc without _id
    $coll->drop;
    $res = $coll->insert_one( { value => "bar" } );
    my @got = $coll->find( {} )->all;
    cmp_deeply(
        \@got,
        bag( { _id => ignore(), value => "bar" } ),
        "insert without _id: hash doc inserted"
    );
    ok( $res->acknowledged, "result acknowledged" );
    is( $got[0]{_id}, $res->inserted_id, "doc has expected inserted _id" );

    # insert arrayref
    $coll->drop;
    $res = $coll->insert_one( [ value => "bar" ] );
    cmp_deeply(
        [ $coll->find( {} )->all ],
        bag( { _id => ignore(), value => "bar" } ),
        "insert without _id: array doc inserted"
    );

    # insert Tie::Ixhash
    $coll->drop;
    $res = $coll->insert_one( Tie::IxHash->new( value => "bar" ) );
    cmp_deeply(
        [ $coll->find( {} )->all ],
        bag( { _id => ignore(), value => "bar" } ),
        "insert without _id: Tie::IxHash doc inserted"
    );

};

subtest "insert_many" => sub {

    # insert docs with mixed _id and not and mixed types
    $coll->drop;
    my $doc = { value => "baz" };
    $res =
      $coll->insert_many( [ { _id => "foo", value => "bar" }, $doc, ] );
    my @got = $coll->find( {} )->all;
    cmp_deeply(
        \@got,
        bag( { _id => "foo", value => "bar" }, { _id => ignore(), value => "baz" }, ),
        "insert many: docs inserted"
    );
    ok( $res->acknowledged, "result acknowledged" );
    isa_ok( $res, "MongoDB::InsertManyResult", "result" );
    cmp_deeply(
        $res->inserted,
        [ { index => 0, _id => 'foo' }, { index => 1, _id => $doc->{_id} } ],
        "inserted contains correct hashrefs"
    );
    cmp_deeply(
        $res->inserted_ids,
        {
            0 => "foo",
            1 => $doc->{_id}
        },
        "inserted_ids contains correct keys/values"
    );

};

done_testing;
