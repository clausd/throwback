package CrudApp::DB::MySQL;
use strict;
use warnings;
use DBI;

#############################################################################
# MySQL Database Adapter for CrudApp
#
# Provides MySQL-specific database operations and SQL translation.
#############################################################################

sub new {
    my ($class, $config) = @_;
    bless {
        config => $config,
        dbh    => undef,
    }, $class;
}

sub connect {
    my $self = shift;

    my $c = $self->{config};
    my $host = $c->{host} || 'localhost';

    $self->{dbh} = DBI->connect(
        "dbi:mysql:database=$c->{name};host=$host",
        $c->{user},
        $c->{pass},
        {
            RaiseError       => 1,
            PrintError       => 0,
            mysql_enable_utf8 => 1,
        }
    ) or die "Cannot connect to MySQL: $DBI::errstr";

    return $self->{dbh};
}

sub dbh { shift->{dbh} }

#############################################################################
# SQL Translation Methods
#
# These return SQL fragments appropriate for MySQL
#############################################################################

# Expression for current timestamp
sub now_expr { 'NOW()' }

# Expression for converting Unix timestamp to datetime
# Usage: my $expr = $adapter->from_unixtime(); # returns 'FROM_UNIXTIME(?)'
sub from_unixtime { 'FROM_UNIXTIME(?)' }

# Quote an identifier (table/column name)
sub quote_ident {
    my ($self, $id) = @_;
    return "`$id`";
}

# Get last inserted ID
sub last_insert_id {
    my ($self, $table) = @_;
    return $self->{dbh}->last_insert_id(undef, undef, $table, undef);
}

# Database type identifier
sub type { 'mysql' }

1;

__END__

=head1 NAME

CrudApp::DB::MySQL - MySQL adapter for CrudApp

=head1 DESCRIPTION

This adapter provides MySQL-specific database operations for CrudApp.

=head1 METHODS

=over 4

=item connect()

Establishes connection to MySQL database. Returns DBI handle.

=item now_expr()

Returns SQL expression for current timestamp: C<NOW()>

=item from_unixtime()

Returns SQL expression for Unix timestamp conversion: C<FROM_UNIXTIME(?)>

=item quote_ident($name)

Quotes an identifier (table/column name) for MySQL: C<`name`>

=item last_insert_id($table)

Returns the last auto-increment ID for the given table.

=item type()

Returns 'mysql'.

=back

=cut
