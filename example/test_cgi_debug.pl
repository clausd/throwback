#!/usr/bin/perl
#
# Debug exactly what happens inside the CGI when processing /todos
#
use strict;
use warnings;
use lib '.', '..';

my $token = shift or die "Usage: $0 <token>\n";

# Set up environment
$ENV{REQUEST_METHOD} = 'GET';
$ENV{PATH_INFO} = '/todos';
$ENV{QUERY_STRING} = '';
$ENV{CONTENT_TYPE} = 'application/json';
$ENV{HTTP_AUTHORIZATION} = "Bearer $token";

print "=" x 60, "\n";
print "CGI Debug - Step by Step\n";
print "=" x 60, "\n\n";

# Load the modules
require MyApi;

print "Step 1: Create app instance\n";
print "-" x 40, "\n";
my $app = MyApi->new;
print "  App created: ", ref($app), "\n\n";

print "Step 2: Run configure (connects to DB)\n";
print "-" x 40, "\n";
$app->configure;
print "  DBH: ", ($app->dbh ? "connected" : "NOT CONNECTED"), "\n\n";

print "Step 3: Check HTTP_AUTHORIZATION env\n";
print "-" x 40, "\n";
print "  ENV{HTTP_AUTHORIZATION}: ", ($ENV{HTTP_AUTHORIZATION} || '(not set)'), "\n";
print "  First 40 chars: ", substr($ENV{HTTP_AUTHORIZATION} || '', 0, 40), "...\n\n";

print "Step 4: Get bearer token\n";
print "-" x 40, "\n";
my $bearer = $app->_get_bearer_token;
print "  Bearer token: ", ($bearer ? substr($bearer, 0, 20) . "..." : "(none)"), "\n";
print "  Full length: ", length($bearer || ''), " chars\n\n";

print "Step 5: Get current_user\n";
print "-" x 40, "\n";
my $user = $app->current_user;
if ($user) {
    print "  User found:\n";
    print "    id: $user->{id}\n";
    print "    username: $user->{username}\n";
    print "    _access keys: ", join(", ", keys %{$user->{_access} || {}}), "\n";
    if ($user->{_access}{tables}) {
        print "    tables: ", join(", ", keys %{$user->{_access}{tables}}), "\n";
    }
} else {
    print "  NO USER RETURNED!\n";

    # Debug why
    print "\n  Debugging current_user failure:\n";

    # Check token extraction
    my $auth_header = $ENV{HTTP_AUTHORIZATION} || '';
    print "    Auth header present: ", ($auth_header ? "yes" : "NO"), "\n";

    my ($extracted) = $auth_header =~ /^Bearer\s+(\S+)/i;
    print "    Token extracted: ", ($extracted ? "yes (".length($extracted)." chars)" : "NO"), "\n";

    if ($extracted) {
        # Try direct DB lookup
        my $session = $app->dbh->selectrow_hashref(
            "SELECT * FROM _sessions WHERE token = ?",
            undef, $extracted
        );
        print "    Session in DB: ", ($session ? "yes (user_id=$session->{user_id})" : "NO"), "\n";

        if ($session) {
            my $valid = $app->dbh->selectrow_array(
                "SELECT 1 FROM _sessions WHERE token = ? AND expires_at > NOW()",
                undef, $extracted
            );
            print "    Session valid: ", ($valid ? "yes" : "NO - EXPIRED"), "\n";

            my $auth_user = $app->dbh->selectrow_hashref(
                "SELECT id, username FROM _auth WHERE id = ?",
                undef, $session->{user_id}
            );
            print "    User in _auth: ", ($auth_user ? "yes ($auth_user->{username})" : "NO"), "\n";
        }
    }
}
print "\n";

print "Step 6: Check access for 'todos' table\n";
print "-" x 40, "\n";
my $can_read = $app->check_access('todos', 'read');
print "  check_access('todos', 'read'): ", ($can_read ? "ALLOWED" : "DENIED"), "\n";

if (!$can_read && $user) {
    print "\n  Debugging access denial:\n";
    my $rules = $user->{_access}{tables} || {};
    print "    User has 'tables' key: ", (exists $user->{_access}{tables} ? "yes" : "NO"), "\n";
    print "    Tables in rules: ", join(", ", keys %$rules), "\n";

    if ($rules->{todos}) {
        print "    'todos' rule exists: yes\n";
        print "    access array: ", join(", ", @{$rules->{todos}{access} || []}), "\n";
    } else {
        print "    'todos' rule exists: NO\n";
    }
}
print "\n";

print "Step 7: What dispatch would do\n";
print "-" x 40, "\n";
my $path = $ENV{PATH_INFO} || '';
$path =~ s|^/||;
my ($action, $id) = split('/', $path, 2);
$action ||= 'index';
print "  Path: $ENV{PATH_INFO}\n";
print "  Action: $action\n";
print "  ID: ", ($id || '(none)'), "\n";
print "  MyApi->can('$action'): ", (MyApi->can($action) ? "yes" : "NO"), "\n";
print "\n";

print "=" x 60, "\n";
print "Summary:\n";
print "  Token valid: ", ($bearer ? "yes" : "no"), "\n";
print "  User loaded: ", ($user ? "yes" : "no"), "\n";
print "  Access granted: ", ($can_read ? "yes" : "no"), "\n";
print "=" x 60, "\n";
