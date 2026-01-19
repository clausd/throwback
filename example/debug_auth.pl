#!/usr/bin/perl
#
# Debug authentication and todos access
#
# Usage: perl debug_auth.pl <username> <password>
#
use strict;
use warnings;
use lib '.', '..';
use MyApi;
use JSON;
use Data::Dumper;

my ($username, $password) = @ARGV;
die "Usage: $0 <username> <password>\n" unless $username && $password;

print "=" x 60, "\n";
print "CrudApp Auth & Todos Debug\n";
print "=" x 60, "\n\n";

my $app = MyApi->new;
$app->configure;

# Step 1: Check user exists
print "Step 1: Looking up user '$username'\n";
print "-" x 40, "\n";

my $user = $app->get_row('_auth', { username => $username });
if ($user) {
    print "  Found user:\n";
    print "    id: $user->{id}\n";
    print "    username: $user->{username}\n";
    print "    salt: $user->{password_salt}\n";
    print "    hash: $user->{password_hash}\n";
    print "    access_rules: $user->{access_rules}\n";
} else {
    print "  ERROR: User '$username' not found in _auth table\n";
    exit 1;
}
print "\n";

# Step 2: Verify password
print "Step 2: Verifying password\n";
print "-" x 40, "\n";

use Digest::SHA qw(sha256_hex);
my $computed_hash = sha256_hex($user->{password_salt} . $password);
print "  Computed hash: $computed_hash\n";
print "  Stored hash:   $user->{password_hash}\n";

if ($computed_hash eq $user->{password_hash}) {
    print "  PASS: Password matches!\n";
} else {
    print "  FAIL: Password does NOT match\n";
    exit 1;
}
print "\n";

# Step 3: Check access rules
print "Step 3: Checking access rules\n";
print "-" x 40, "\n";

my $access = eval { decode_json($user->{access_rules} || '{}') } || {};
print "  Parsed access rules:\n";
print Dumper($access);

if ($access->{tables} && $access->{tables}{todos}) {
    print "  Todos access config:\n";
    print "    access: ", join(', ', @{$access->{tables}{todos}{access} || []}), "\n";
    if ($access->{tables}{todos}{filters}) {
        print "    filters: ", encode_json($access->{tables}{todos}{filters}), "\n";
    }
} else {
    print "  WARNING: No 'todos' entry in access rules!\n";
    print "  User needs access_rules like:\n";
    print '  {"tables":{"todos":{"access":["create","read","update","delete"],"filters":{"user_id":"$user.id"}}}}'."\n";
}
print "\n";

# Step 4: Simulate auth check
print "Step 4: Simulating access check for 'todos' table\n";
print "-" x 40, "\n";

# Manually set current user (simulating what current_user() would return)
$app->{_current_user} = $user;
$app->{_current_user}{_access} = $access;

my @ops = ('read', 'create', 'update', 'delete');
for my $op (@ops) {
    my $allowed = $app->check_access('todos', $op);
    print "  $op: ", ($allowed ? "ALLOWED" : "DENIED"), "\n";
}
print "\n";

# Step 5: Check filters
print "Step 5: Checking filters for todos\n";
print "-" x 40, "\n";

my $filters = $app->get_filters('todos');
print "  Resolved filters: ", encode_json($filters), "\n";
if ($filters->{user_id}) {
    print "  user_id filter = $filters->{user_id} (should match user id: $user->{id})\n";
}
print "\n";

# Step 6: Try to fetch todos
print "Step 6: Fetching todos for user\n";
print "-" x 40, "\n";

my $todos = $app->get_rows('todos', $filters, 10, 0);
print "  Found ", scalar(@$todos), " todos\n";
for my $todo (@$todos) {
    print "    - [$todo->{id}] $todo->{title} (done: $todo->{done})\n";
}
print "\n";

# Step 7: Check active sessions
print "Step 7: Checking active sessions for user\n";
print "-" x 40, "\n";

my $sessions = $app->query_rows(
    "SELECT * FROM _sessions WHERE user_id = ? AND expires_at > NOW()",
    $user->{id}
);
print "  Found ", scalar(@$sessions), " active sessions\n";
for my $sess (@$sessions) {
    print "    - token: ", substr($sess->{token}, 0, 16), "...\n";
    print "      expires: $sess->{expires_at}\n";
}
print "\n";

print "=" x 60, "\n";
print "Debug complete\n";
print "=" x 60, "\n";
