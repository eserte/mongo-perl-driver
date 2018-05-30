#  Copyright 2014 - present MongoDB, Inc.
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

use strict;
use warnings;
package MongoDB::Op::_Command;

# Encapsulate running a command and returning a MongoDB::CommandResult

use version;
our $VERSION = 'v1.999.0';

use Moo;

use MongoDB::_Constants;
use MongoDB::_Types qw(
    Document
    ReadPreference
);
use Types::Standard qw(
    CodeRef
    HashRef
    Maybe
    InstanceOf
);

use namespace::clean;

has query => (
    is       => 'ro',
    required => 1,
    writer   => '_set_query',
    isa      => Document,
);

has query_flags => (
    is       => 'ro',
    required => 1,
    isa      => HashRef,
);

has read_preference => (
    is  => 'ro',
    isa => Maybe [ReadPreference],
);

with $_ for qw(
  MongoDB::Role::_PrivateConstructor
  MongoDB::Role::_DatabaseOp
  MongoDB::Role::_ReadPrefModifier
  MongoDB::Role::_SessionSupport
  MongoDB::Role::_CommandMonitoring
);

my %IS_NOT_COMPRESSIBLE = map { ($_ => 1) } qw(
    ismaster
    saslstart
    saslcontinue
    getnonce
    authenticate
    createuser
    updateuser
    copydbsaslstart
    copydbgetnonce
    copydb
);

sub execute {
    my ( $self, $link, $topology_type ) = @_;
    $topology_type ||= 'Single'; # if not specified, assume direct

    $self->_apply_session_and_cluster_time( $link, \$self->{query} );

    # $query is passed as a reference because it *may* be replaced
    $self->_apply_read_prefs( $link, $topology_type, $self->{query_flags}, \$self->{query});

    my ( $op_bson, $request_id ) =
      MongoDB::_Protocol::write_query( $self->{db_name} . '.$cmd',
        $self->{bson_codec}->encode_one( $self->{query} ), undef, 0, -1, $self->{query_flags});

    if ( length($op_bson) > MAX_BSON_WIRE_SIZE ) {
        # XXX should this become public?
        MongoDB::_CommandSizeError->throw(
            message => "database command too large",
            size    => length $op_bson,
        );
    }

    $self->publish_command_started( $link, $self->{query}, $request_id )
      if $self->monitoring_callback;

    my %write_opt;
    $write_opt{disable_compression} = do {
        my $doc = $self->{query};
        my $type = ref $doc;
        (
            $type eq 'ARRAY' ? $IS_NOT_COMPRESSIBLE{ $doc->[0] }
          : $type eq 'Tie::IxHash' ? $doc->Keys(0)
          : do { # hashlike?
              my $disable;
              DOC_FIELD: for my $name (keys %$doc) {
                  if ($IS_NOT_COMPRESSIBLE{lc $name}) {
                      $disable = 1;
                      last DOC_FIELD;
                  }
              }
              $disable
            }
        )
    };

    my $result;
    eval {
        $link->write( $op_bson, \%write_opt ),
        ( $result = MongoDB::_Protocol::parse_reply( $link->read, $request_id ) );
    };
    if ( my $err = $@ ) {
        $self->publish_command_exception($err) if $self->monitoring_callback;
        die $err;
    }

    $self->publish_command_reply( $result->{docs} )
      if $self->monitoring_callback;

    my $res = MongoDB::CommandResult->_new(
        output => $self->{bson_codec}->decode_one( $result->{docs} ),
        address => $link->address,
    );

    # Must happen even on an error (ie. the command fails)
    $self->_update_operation_time( $res );

    $res->assert;

    $self->_update_session_and_cluster_time($res);

    return $res;
}

1;
