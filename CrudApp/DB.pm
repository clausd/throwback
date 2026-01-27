package CrudApp::DB;
use strict;
use warnings;

#############################################################################
# CrudApp Database Adapter Factory
#
# Creates the appropriate database adapter based on configuration.
#
# Usage:
#   use CrudApp::DB;
#   my $adapter = CrudApp::DB->new({ type => 'sqlite', path => './dev.db' });
#   my $dbh = $adapter->connect();
#############################################################################

sub new {
    my ($class, $config) = @_;

    my $type = $config->{type} || 'mysql';

    # Map type to adapter class
    my %adapters = (
        mysql  => 'CrudApp::DB::MySQL',
        sqlite => 'CrudApp::DB::SQLite',
    );

    my $adapter_class = $adapters{lc($type)}
        or die "Unknown database type: $type (supported: mysql, sqlite)";

    # Load the adapter module
    eval "require $adapter_class"
        or die "Cannot load database adapter $adapter_class: $@";

    return $adapter_class->new($config);
}

1;

__END__

=head1 NAME

CrudApp::DB - Database adapter factory for CrudApp

=head1 SYNOPSIS

    use CrudApp::DB;

    # SQLite for development
    my $adapter = CrudApp::DB->new({
        type => 'sqlite',
        path => './dev.db'
    });

    # MySQL for production
    my $adapter = CrudApp::DB->new({
        type => 'mysql',
        name => 'mydb',
        user => 'root',
        pass => 'secret',
        host => 'localhost'
    });

    # Get database handle
    my $dbh = $adapter->connect();

    # Use adapter methods for portable SQL
    my $now = $adapter->now_expr();           # NOW() or datetime('now')
    my $ts  = $adapter->from_unixtime();      # FROM_UNIXTIME(?) or datetime(?, 'unixepoch')

=head1 SUPPORTED ADAPTERS

=over 4

=item * mysql - MySQL/MariaDB via DBD::mysql

=item * sqlite - SQLite via DBD::SQLite

=back

=cut
