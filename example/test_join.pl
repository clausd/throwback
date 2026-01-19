#!/usr/bin/perl
#
# Test the exact JOIN query that current_user uses
#
use strict;
use warnings;
use lib '.', '..';

my $token = shift or die "Usage: $0 <token>\n";

require MyApi;
my $app = MyApi->new;
$app->configure;

my $dbh = $app->dbh;

print "Testing the exact JOIN query from current_user():\n\n";

# This is the exact query from CrudApp.pm line 265-269
my $sql = "SELECT u.* FROM _auth u
     JOIN _sessions s ON s.user_id = u.id
     WHERE s.token = ? AND s.expires_at > NOW()";

print "SQL:\n$sql\n\n";
print "Token: $token\n\n";

my $row = $dbh->selectrow_hashref($sql, undef, $token);

if ($row) {
    print "SUCCESS! Query returned:\n";
    for my $k (sort keys %$row) {
        my $v = $row->{$k} // '(null)';
        $v = substr($v, 0, 50) . '...' if length($v) > 50;
        print "  $k: $v\n";
    }
} else {
    print "FAILED! Query returned NULL\n\n";

    # Debug step by step
    print "Debugging:\n";

    # Check if token exists
    my $sess = $dbh->selectrow_hashref(
        "SELECT * FROM _sessions WHERE token = ?", undef, $token
    );
    print "1. Token in _sessions: ", ($sess ? "YES" : "NO"), "\n";

    if ($sess) {
        print "   user_id: $sess->{user_id}\n";
        print "   expires_at: $sess->{expires_at}\n";

        # Check NOW() comparison
        my ($now) = $dbh->selectrow_array("SELECT NOW()");
        print "   NOW(): $now\n";

        my ($cmp) = $dbh->selectrow_array(
            "SELECT expires_at > NOW() FROM _sessions WHERE token = ?",
            undef, $token
        );
        print "   expires_at > NOW(): ", ($cmp ? "TRUE" : "FALSE"), "\n";

        # Check user exists
        my $user = $dbh->selectrow_hashref(
            "SELECT * FROM _auth WHERE id = ?", undef, $sess->{user_id}
        );
        print "2. User in _auth: ", ($user ? "YES (id=$user->{id})" : "NO"), "\n";

        # Try the join without the date check
        my $join_no_date = $dbh->selectrow_hashref(
            "SELECT u.* FROM _auth u JOIN _sessions s ON s.user_id = u.id WHERE s.token = ?",
            undef, $token
        );
        print "3. JOIN without date check: ", ($join_no_date ? "SUCCESS" : "FAILED"), "\n";

        # Try with explicit date check
        my $join_with_date = $dbh->selectrow_hashref(
            "SELECT u.* FROM _auth u JOIN _sessions s ON s.user_id = u.id WHERE s.token = ? AND s.expires_at > ?",
            undef, $token, $now
        );
        print "4. JOIN with explicit NOW: ", ($join_with_date ? "SUCCESS" : "FAILED"), "\n";
    }
}
