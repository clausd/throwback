package CrudApp::DB::SQLite;
use strict;
use warnings;
use DBI;

#############################################################################
# SQLite Database Adapter for CrudApp
#
# Provides SQLite-specific database operations and SQL translation.
# Ideal for local development on Mac without MySQL.
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

    my $path = $self->{config}{path}
        or die "SQLite requires 'path' configuration";

    $self->{dbh} = DBI->connect(
        "dbi:SQLite:dbname=$path",
        '', '',
        {
            RaiseError     => 1,
            PrintError     => 0,
            sqlite_unicode => 1,
        }
    ) or die "Cannot connect to SQLite: $DBI::errstr";

    # Enable foreign keys (disabled by default in SQLite)
    $self->{dbh}->do("PRAGMA foreign_keys = ON");

    return $self->{dbh};
}

sub dbh { shift->{dbh} }

#############################################################################
# SQL Translation Methods
#
# These return SQL fragments appropriate for SQLite
#############################################################################

# Expression for current timestamp
sub now_expr { "datetime('now')" }

# Expression for converting Unix timestamp to datetime
# Usage: my $expr = $adapter->from_unixtime(); # returns "datetime(?, 'unixepoch')"
sub from_unixtime { "datetime(?, 'unixepoch')" }

# Quote an identifier (table/column name)
# SQLite supports backticks for MySQL compatibility, but double quotes are standard
sub quote_ident {
    my ($self, $id) = @_;
    return qq{"$id"};
}

# Get last inserted ID
sub last_insert_id {
    my ($self, $table) = @_;
    # SQLite's last_insert_id works without table name
    return $self->{dbh}->last_insert_id(undef, undef, undef, undef);
}

# Database type identifier
sub type { 'sqlite' }

1;

__END__

=head1 NAME

CrudApp::DB::SQLite - SQLite adapter for CrudApp

=head1 DESCRIPTION

This adapter provides SQLite-specific database operations for CrudApp.
Perfect for local development without requiring a MySQL installation.

=head1 METHODS

=over 4

=item connect()

Establishes connection to SQLite database file. Creates the file if
it doesn't exist. Returns DBI handle.

=item now_expr()

Returns SQL expression for current timestamp: C<datetime('now')>

=item from_unixtime()

Returns SQL expression for Unix timestamp conversion: C<datetime(?, 'unixepoch')>

=item quote_ident($name)

Quotes an identifier (table/column name) for SQLite: C<"name">

=item last_insert_id($table)

Returns the last auto-increment ID (table parameter ignored in SQLite).

=item type()

Returns 'sqlite'.

=back

=head1 NOTES

=head2 Foreign Keys

SQLite has foreign keys disabled by default. This adapter automatically
enables them with C<PRAGMA foreign_keys = ON>.

=head2 Schema Differences

SQLite uses different syntax for some features:

    MySQL                          SQLite
    -----                          ------
    INT AUTO_INCREMENT             INTEGER PRIMARY KEY AUTOINCREMENT
    NOW()                          datetime('now')
    FROM_UNIXTIME(?)               datetime(?, 'unixepoch')
    ON UPDATE CURRENT_TIMESTAMP    Requires trigger

See C<dev/schema_sqlite.sql> for a SQLite-compatible schema.

=cut
