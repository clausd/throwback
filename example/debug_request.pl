#!/usr/bin/perl
#
# Debug a specific API request
#
# Usage:
#   perl debug_request.pl GET /todos <token>
#   perl debug_request.pl POST /todos <token> '{"title":"Test todo"}'
#
use strict;
use warnings;
use lib '.', '..';
use MyApi;
use JSON;
use Data::Dumper;

my ($method, $path, $token, $body) = @ARGV;
die "Usage: $0 <METHOD> <PATH> <TOKEN> [JSON_BODY]\n" unless $method && $path && $token;

print "=" x 60, "\n";
print "CrudApp Request Debug\n";
print "=" x 60, "\n\n";

print "Request:\n";
print "  Method: $method\n";
print "  Path: $path\n";
print "  Token: ", substr($token, 0, 16), "...\n";
print "  Body: ", ($body || '(none)'), "\n";
print "\n";

# Set up CGI environment
$ENV{REQUEST_METHOD} = $method;
$ENV{PATH_INFO} = $path;
$ENV{HTTP_AUTHORIZATION} = "Bearer $token";
$ENV{CONTENT_TYPE} = 'application/json' if $body;
$ENV{QUERY_STRING} = '';

# Mock STDIN for POST body
if ($body) {
    open my $stdin, '<', \$body;
    *STDIN = $stdin;
}

my $app = MyApi->new;
$app->{_cgi} = CGI->new;
$app->configure;

# Step 1: Validate token
print "Step 1: Validating token\n";
print "-" x 40, "\n";

my $session = $app->query_row(
    "SELECT * FROM _sessions WHERE token = ?",
    $token
);

if ($session) {
    print "  Session found:\n";
    print "    user_id: $session->{user_id}\n";
    print "    expires_at: $session->{expires_at}\n";

    # Check if expired
    my $valid = $app->query_value(
        "SELECT 1 FROM _sessions WHERE token = ? AND expires_at > NOW()",
        $token
    );
    print "    status: ", ($valid ? "VALID" : "EXPIRED"), "\n";
} else {
    print "  ERROR: Token not found in _sessions!\n";
}
print "\n";

# Step 2: Get current user
print "Step 2: Loading current user\n";
print "-" x 40, "\n";

my $user = $app->current_user;
if ($user) {
    print "  User loaded:\n";
    print "    id: $user->{id}\n";
    print "    username: $user->{username}\n";
    print "    access rules: ", encode_json($user->{_access} || {}), "\n";
} else {
    print "  ERROR: current_user() returned undef!\n";
    print "  This means the token lookup failed.\n";
}
print "\n";

# Step 3: Parse path
print "Step 3: Parsing request path\n";
print "-" x 40, "\n";

my $parsed_path = $path;
$parsed_path =~ s|^/||;
my ($action, $id) = split('/', $parsed_path, 2);
$action ||= 'index';

print "  Action: $action\n";
print "  ID: ", ($id || '(none)'), "\n";
print "\n";

# Step 4: Check if method exists
print "Step 4: Checking if endpoint exists\n";
print "-" x 40, "\n";

my $can = MyApi->can($action);
print "  MyApi->can('$action'): ", ($can ? "YES" : "NO"), "\n";

if (!$can) {
    print "  ERROR: No method '$action' in MyApi!\n";
    print "  Available methods in MyApi:\n";
    no strict 'refs';
    for my $name (sort keys %{'MyApi::'}) {
        next if $name =~ /^(BEGIN|END|AUTOLOAD|DESTROY|ISA|VERSION)$/;
        next unless defined &{"MyApi::$name"};
        print "    - $name\n";
    }
}
print "\n";

# Step 5: Check access
print "Step 5: Checking access for '$action'\n";
print "-" x 40, "\n";

if ($user) {
    # For crud endpoints, the table name is the action
    my $table = $action;
    my $op = $method eq 'GET' ? 'read'
           : $method eq 'DELETE' ? 'delete'
           : 'create';  # POST

    print "  Table: $table\n";
    print "  Operation: $op\n";

    my $allowed = $app->check_access($table, $op);
    print "  Access: ", ($allowed ? "ALLOWED" : "DENIED"), "\n";

    if (!$allowed) {
        print "\n  Debugging access check:\n";
        print "    anon_access: ", encode_json($app->anon_access), "\n";
        print "    user access_rules: ", encode_json($user->{_access} || {}), "\n";
    }
} else {
    print "  Cannot check access - no authenticated user\n";
}
print "\n";

# Step 6: If body provided, parse it
if ($body) {
    print "Step 6: Parsing JSON body\n";
    print "-" x 40, "\n";

    my $parsed = $app->json_input;
    if ($parsed) {
        print "  Parsed OK:\n";
        print Dumper($parsed);
    } else {
        print "  ERROR: Failed to parse JSON body\n";
    }
    print "\n";
}

print "=" x 60, "\n";
print "Debug complete\n";
print "\n";
print "To make the actual request, run:\n";
print "  curl -X $method https://classy.dk/todo$path \\\n";
print "    -H 'Authorization: Bearer $token'";
print " \\\n    -H 'Content-Type: application/json' \\\n    -d '$body'" if $body;
print "\n";
print "=" x 60, "\n";
