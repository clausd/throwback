#!/usr/bin/perl
#
# CrudApp SQLite Database Setup Script
#
# Usage:
#   perl dev/setup.pl                    # Initialize database with schema
#   perl dev/setup.pl --demo             # Also create demo user
#   perl dev/setup.pl --config myapp.conf
#
# This script:
#   1. Loads configuration from crudapp.conf (or specified file)
#   2. Creates SQLite database file if it doesn't exist
#   3. Loads the SQLite schema
#   4. Optionally creates a demo user for testing
#

use strict;
use warnings;
use lib '.';
use DBI;
use Getopt::Long;
use File::Basename;
use File::Spec;

# Find our location and add to lib path
my $script_dir = dirname(File::Spec->rel2abs(__FILE__));
my $base_dir = dirname($script_dir);
chdir $base_dir or die "Cannot chdir to $base_dir: $!";

# Add base dir to lib path (but only if it's set)
if ($base_dir) {
    unshift @INC, $base_dir;
}
use CrudApp::Config;

# Parse command line options
my $config_file = 'crudapp.conf';
my $schema_file = 'dev/schema_sqlite.sql';
my $create_demo = 0;
my $help = 0;

GetOptions(
    'config=s' => \$config_file,
    'schema=s' => \$schema_file,
    'demo'     => \$create_demo,
    'help|h'   => \$help,
) or die "Error in command line arguments\n";

if ($help) {
    print <<'USAGE';
CrudApp SQLite Database Setup

Usage: perl dev/setup.pl [OPTIONS]

Options:
  --config FILE   Configuration file (default: crudapp.conf)
  --schema FILE   Schema file (default: dev/schema_sqlite.sql)
  --demo          Create demo user (username: demo, password: demo123)
  --help, -h      Show this help message

Examples:
  perl dev/setup.pl              # Basic setup
  perl dev/setup.pl --demo       # Setup with demo user

USAGE
    exit 0;
}

# Load configuration
print "Loading configuration from: $config_file\n";
my $config = CrudApp::Config->load($config_file);

# Verify SQLite configuration
my $db_type = $config->{database}{type} || '';
unless ($db_type eq 'sqlite') {
    die "Error: Database type must be 'sqlite' for this setup script.\n"
      . "Current type: '$db_type'\n"
      . "Please configure [database] type = sqlite in $config_file\n";
}

my $db_path = $config->{database}{path}
    or die "Error: No database path configured.\n"
         . "Please set [database] path = ./dev.db in $config_file\n";

# Check schema file exists
unless (-f $schema_file) {
    die "Error: Schema file not found: $schema_file\n";
}

print "=" x 50, "\n";
print "CrudApp SQLite Setup\n";
print "=" x 50, "\n";
print "Database: $db_path\n";
print "Schema:   $schema_file\n";
print "=" x 50, "\n\n";

# Create database directory if needed
my $db_dir = dirname($db_path);
if ($db_dir && $db_dir ne '.' && !-d $db_dir) {
    print "Creating directory: $db_dir\n";
    mkdir $db_dir or die "Cannot create directory $db_dir: $!";
}

# Connect to SQLite (creates file if it doesn't exist)
print "Connecting to SQLite database...\n";
my $dbh = DBI->connect(
    "dbi:SQLite:dbname=$db_path",
    '', '',
    {
        RaiseError     => 1,
        PrintError     => 0,
        sqlite_unicode => 1,
    }
) or die "Cannot connect to SQLite: $DBI::errstr";

# Enable foreign keys
$dbh->do("PRAGMA foreign_keys = ON");

# Load and execute schema
print "Loading schema from: $schema_file\n";
open my $fh, '<', $schema_file or die "Cannot read $schema_file: $!";
local $/;
my $schema = <$fh>;
close $fh;

# Execute schema statements
# Split on semicolons but be careful about triggers which contain semicolons
my @statements;
my $current = '';
my $in_trigger = 0;

for my $line (split /\n/, $schema) {
    # Skip comments and empty lines for splitting purposes
    next if $line =~ /^\s*--/ && !$in_trigger;

    $in_trigger = 1 if $line =~ /CREATE\s+TRIGGER/i;
    $current .= "$line\n";

    if ($line =~ /;\s*$/) {
        if ($in_trigger && $line =~ /END\s*;\s*$/i) {
            push @statements, $current;
            $current = '';
            $in_trigger = 0;
        } elsif (!$in_trigger) {
            push @statements, $current;
            $current = '';
        }
    }
}
push @statements, $current if $current =~ /\S/;

my $executed = 0;
for my $stmt (@statements) {
    $stmt =~ s/^\s+//;
    $stmt =~ s/\s+$//;
    next unless $stmt;
    next if $stmt =~ /^--/;  # Skip pure comment blocks

    eval { $dbh->do($stmt) };
    if ($@) {
        # Ignore "already exists" errors
        unless ($@ =~ /already exists/i) {
            warn "Warning: $@\nStatement: $stmt\n\n";
        }
    } else {
        $executed++;
    }
}

print "Schema loaded successfully ($executed statements executed).\n\n";

# Create demo user if requested
if ($create_demo) {
    print "Creating demo user...\n";

    # Check if demo user already exists
    my ($exists) = $dbh->selectrow_array(
        "SELECT 1 FROM _auth WHERE username = ?",
        undef, 'demo'
    );

    if ($exists) {
        print "Demo user already exists, skipping.\n";
    } else {
        # Generate salt and hash password
        require Digest::SHA;

        my $salt = '';
        if (open my $urandom, '<', '/dev/urandom') {
            read $urandom, my $random, 16;
            close $urandom;
            $salt = Digest::SHA::sha256_hex($random);
        } else {
            $salt = Digest::SHA::sha256_hex(time() . $$ . rand());
        }
        $salt = substr($salt, 0, 32);

        my $password = 'demo123';
        my $hash = Digest::SHA::sha256_hex($salt . $password);

        # Access rules for demo user
        require JSON;
        my $access_rules = JSON::encode_json({
            tables => {
                todos => {
                    access => ['create', 'read', 'update', 'delete'],
                    filters => { user_id => '$user.id' }
                }
            }
        });

        $dbh->do(
            "INSERT INTO _auth (username, password_salt, password_hash, access_rules) VALUES (?, ?, ?, ?)",
            undef, 'demo', $salt, $hash, $access_rules
        );

        my $user_id = $dbh->last_insert_id(undef, undef, undef, undef);
        print "Created demo user (id=$user_id)\n";
        print "  Username: demo\n";
        print "  Password: demo123\n";
    }
}

$dbh->disconnect;

print "\n";
print "=" x 50, "\n";
print "Setup complete!\n";
print "=" x 50, "\n";
print "\nNext steps:\n";
print "  1. Start the development server:\n";
print "     perl dev/runner.pl\n";
print "\n";
print "  2. Open in browser:\n";
print "     http://localhost:3000/\n";
print "\n";

if ($create_demo) {
    print "  3. Login with demo user:\n";
    print "     Username: demo\n";
    print "     Password: demo123\n";
    print "\n";
}
