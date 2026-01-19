#!/usr/bin/perl
#
# Debug token lookup specifically
#
# Usage: perl debug_token.pl <token>
#
use strict;
use warnings;
use lib '.', '..';
use DBI;
use JSON;

# Read database config from MyApi
require MyApi;
my $app = MyApi->new;
$app->configure;

my $token = shift or die "Usage: $0 <token>\n";
my $dbh = $app->dbh;

print "=" x 60, "\n";
print "Token Debug\n";
print "=" x 60, "\n\n";

print "Token: ", substr($token, 0, 20), "...\n\n";

# Step 1: Check _sessions table directly
print "Step 1: Direct _sessions query\n";
print "-" x 40, "\n";

my $session = $dbh->selectrow_hashref(
    "SELECT * FROM _sessions WHERE token = ?",
    undef, $token
);

if ($session) {
    print "  Found session:\n";
    for my $k (sort keys %$session) {
        print "    $k: $session->{$k}\n";
    }
} else {
    print "  NO SESSION FOUND!\n";
    print "  Token may be truncated or wrong.\n";
}
print "\n";

# Step 2: Check if session is expired
print "Step 2: Check expiration\n";
print "-" x 40, "\n";

my $valid = $dbh->selectrow_array(
    "SELECT 1 FROM _sessions WHERE token = ? AND expires_at > NOW()",
    undef, $token
);
print "  Token valid (not expired): ", ($valid ? "YES" : "NO"), "\n";

my ($now, $expires) = $dbh->selectrow_array(
    "SELECT NOW(), expires_at FROM _sessions WHERE token = ?",
    undef, $token
);
print "  Server NOW(): $now\n" if $now;
print "  Token expires: $expires\n" if $expires;
print "\n";

# Step 3: Check user exists
print "Step 3: Check user exists\n";
print "-" x 40, "\n";

if ($session && $session->{user_id}) {
    my $user = $dbh->selectrow_hashref(
        "SELECT id, username, access_rules FROM _auth WHERE id = ?",
        undef, $session->{user_id}
    );
    if ($user) {
        print "  User found:\n";
        print "    id: $user->{id}\n";
        print "    username: $user->{username}\n";
        print "    access_rules: $user->{access_rules}\n";
    } else {
        print "  ERROR: User ID $session->{user_id} NOT FOUND in _auth!\n";
    }
}
print "\n";

# Step 4: Test the exact JOIN query used by current_user()
print "Step 4: Test JOIN query (exactly as CrudApp uses)\n";
print "-" x 40, "\n";

my $row = $dbh->selectrow_hashref(
    "SELECT u.* FROM _auth u
     JOIN _sessions s ON s.user_id = u.id
     WHERE s.token = ? AND s.expires_at > NOW()",
    undef, $token
);

if ($row) {
    print "  JOIN query succeeded:\n";
    print "    id: $row->{id}\n";
    print "    username: $row->{username}\n";
} else {
    print "  JOIN query returned NULL!\n";
    print "\n  Possible causes:\n";
    print "    1. Token not in _sessions\n";
    print "    2. Session expired (expires_at <= NOW())\n";
    print "    3. user_id doesn't match any _auth.id\n";

    # Debug each condition
    print "\n  Debugging:\n";

    my $s_exists = $dbh->selectrow_array(
        "SELECT COUNT(*) FROM _sessions WHERE token = ?", undef, $token
    );
    print "    Token in _sessions: ", ($s_exists ? "YES" : "NO"), "\n";

    my $s_valid = $dbh->selectrow_array(
        "SELECT COUNT(*) FROM _sessions WHERE token = ? AND expires_at > NOW()",
        undef, $token
    );
    print "    Token not expired: ", ($s_valid ? "YES" : "NO"), "\n";

    if ($session) {
        my $u_exists = $dbh->selectrow_array(
            "SELECT COUNT(*) FROM _auth WHERE id = ?",
            undef, $session->{user_id}
        );
        print "    User $session->{user_id} in _auth: ", ($u_exists ? "YES" : "NO"), "\n";
    }
}
print "\n";

# Step 5: Show all sessions
print "Step 5: All sessions in database\n";
print "-" x 40, "\n";

my $sessions = $dbh->selectall_arrayref(
    "SELECT token, user_id, expires_at, expires_at > NOW() as valid FROM _sessions",
    { Slice => {} }
);

for my $s (@$sessions) {
    print "  Token: ", substr($s->{token}, 0, 16), "...\n";
    print "    user_id: $s->{user_id}, expires: $s->{expires_at}, valid: $s->{valid}\n";
}
print "  (Total: ", scalar(@$sessions), " sessions)\n" if @$sessions;
print "  No sessions found\n" unless @$sessions;

print "\n";
print "=" x 60, "\n";
