#!/usr/bin/perl
#
# Test the CGI script directly, bypassing Apache
#
# Usage: perl test_cgi_direct.pl <token>
#
use strict;
use warnings;

my $token = shift or die "Usage: $0 <token>\n";

print "=" x 60, "\n";
print "Direct CGI Test\n";
print "=" x 60, "\n\n";

# Set up CGI environment exactly as Apache would
$ENV{REQUEST_METHOD} = 'GET';
$ENV{PATH_INFO} = '/todos';
$ENV{QUERY_STRING} = '';
$ENV{CONTENT_TYPE} = 'application/json';
$ENV{HTTP_AUTHORIZATION} = "Bearer $token";
$ENV{SCRIPT_NAME} = '/api.cgi';
$ENV{SERVER_NAME} = 'localhost';
$ENV{SERVER_PORT} = '80';
$ENV{SERVER_PROTOCOL} = 'HTTP/1.1';
$ENV{GATEWAY_INTERFACE} = 'CGI/1.1';

print "Environment set:\n";
print "  REQUEST_METHOD: $ENV{REQUEST_METHOD}\n";
print "  PATH_INFO: $ENV{PATH_INFO}\n";
print "  HTTP_AUTHORIZATION: Bearer ", substr($token, 0, 16), "...\n";
print "\n";

print "Calling api.cgi...\n";
print "-" x 60, "\n";

# Capture output
my $output = '';
{
    # Redirect STDOUT to capture CGI output
    open my $oldout, '>&', \*STDOUT;
    close STDOUT;
    open STDOUT, '>', \$output;

    # Run the CGI
    do './api.cgi';

    # Restore STDOUT
    close STDOUT;
    open STDOUT, '>&', $oldout;
}

print $output;
print "\n";
print "-" x 60, "\n";
print "End of CGI output\n";
print "=" x 60, "\n";
