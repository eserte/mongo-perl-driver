#
#  Copyright 2009-2013 MongoDB, Inc.
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
use Test::More;
use Test::Exception;

use MongoDB;

use lib "t/lib";
use MongoDBTest '$conn', '$testdb';

plan tests => 9;

{
    my $regexp = MongoDB::BSON::Regexp->new( pattern => 'foo*bar' );
    is $regexp->pattern, 'foo*bar';
}

{ 
    my $regexp = MongoDB::BSON::Regexp->new( pattern => 'bar?baz', flags => 'msi' );
    is $regexp->pattern, 'bar?baz';
    is $regexp->flags, 'ims';
}

throws_ok {
    my $regexp = MongoDB::BSON::Regexp->new( pattern => 'narf', flags => 'xyz' );
} qr/Regexp flag \w is not supported/, 'exception on invalid flag';


{
    $conn->inflate_regexps( 1 );

    $conn->get_database( "test_database" )->get_collection( "test_collection" )->insert( {
        _id => 'spl0rt',
        foo => MongoDB::BSON::Regexp->new( pattern => 'foo.+bar', flags => 'ims' ) } 
    );

    my $doc = $conn->get_database( "test_database" )->get_collection( "test_collection" )->find_one( { _id => 'spl0rt' } );
    ok $doc->{foo};
    ok ref $doc->{foo};
    isa_ok $doc->{foo}, 'MongoDB::BSON::Regexp';

    is $doc->{foo}->pattern, 'foo.+bar';
    is $doc->{foo}->flags, 'ims';

    $conn->get_database( "test_database" )->drop;
}
