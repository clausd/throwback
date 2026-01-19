#!/usr/bin/perl
#
# Create a user for the CrudApp API
#
# Usage:
#   perl create_user.pl <username> <password> [access_rules.json]
#
# Examples:
#   perl create_user.pl demo demo123
#   perl create_user.pl admin adminpass admin_access.json
#
use strict;
use warnings;
use lib '.', '..';
use MyApi;
use JSON;

my ($username, $password, $rules_file) = @ARGV;

unless ($username && $password) {
    die "Usage: $0 <username> <password> [access_rules.json]\n";
}

# Default access rules: full access to todos, filtered by user_id
my $access_rules = {
    tables => {
        todos => {
            access => ['create', 'read', 'update', 'delete'],
            filters => { user_id => '$user.id' }
        }
    }
};

# Load custom rules if provided
if ($rules_file && -f $rules_file) {
    open my $fh, '<', $rules_file or die "Cannot read $rules_file: $!\n";
    local $/;
    my $json = <$fh>;
    close $fh;
    $access_rules = decode_json($json);
    print "Loaded access rules from $rules_file\n";
}

# Create the user
my $app = MyApi->new;
$app->configure;

eval {
    my $id = $app->create_user($username, $password, $access_rules);
    print "Created user '$username' with ID $id\n";
    print "Access rules: ", encode_json($access_rules), "\n";
};

if ($@) {
    if ($@ =~ /Duplicate entry/) {
        die "Error: User '$username' already exists\n";
    }
    die "Error creating user: $@\n";
}
