#!/usr/bin/perl
#
# CrudApp Server Compatibility Test
#
# Run this on your server to verify all dependencies are available
# and the framework will work correctly.
#
# Usage: perl test_server.pl
#
use strict;
use warnings;

print "=" x 60, "\n";
print "CrudApp Server Compatibility Test\n";
print "=" x 60, "\n\n";

my $all_pass = 1;

# Test 1: Perl version
print "Test 1: Perl Version\n";
print "-" x 50, "\n";
if ($] >= 5.010) {
    print "  PASS: Perl $] (>= 5.10 required)\n";
} else {
    print "  FAIL: Perl $] is too old (need >= 5.10)\n";
    $all_pass = 0;
}
print "\n";

# Test 2: Required modules
print "Test 2: Required Modules\n";
print "-" x 50, "\n";

my @required = (
    ['CGI', 'Core module for handling requests'],
    ['DBI', 'Database interface'],
    ['JSON', 'JSON encoding/decoding'],
    ['Digest::SHA', 'Password hashing (core since 5.10)'],
);

for my $mod (@required) {
    my ($name, $desc) = @$mod;
    eval "require $name";
    if ($@) {
        print "  FAIL: $name - NOT INSTALLED\n";
        print "        ($desc)\n";
        $all_pass = 0;
    } else {
        my $ver = eval "\$${name}::VERSION" || 'unknown';
        print "  PASS: $name ($ver)\n";
    }
}
print "\n";

# Test 3: MySQL driver
print "Test 3: MySQL Driver\n";
print "-" x 50, "\n";
eval { require DBD::mysql };
if ($@) {
    print "  FAIL: DBD::mysql - NOT INSTALLED\n";
    print "        (Required for MySQL database access)\n";
    $all_pass = 0;
} else {
    print "  PASS: DBD::mysql ($DBD::mysql::VERSION)\n";
}
print "\n";

# Test 4: CrudApp loads
print "Test 4: CrudApp Module\n";
print "-" x 50, "\n";
eval {
    require CrudApp;
    print "  PASS: CrudApp ($CrudApp::VERSION) loaded successfully\n";
};
if ($@) {
    print "  FAIL: CrudApp failed to load\n";
    print "        Error: $@\n";
    $all_pass = 0;
}
print "\n";

# Test 5: MyApi loads (if present)
print "Test 5: MyApi Module (example app)\n";
print "-" x 50, "\n";
if (-f 'MyApi.pm') {
    eval { require MyApi };
    if ($@) {
        print "  FAIL: MyApi.pm failed to load\n";
        my $err = $@;
        $err =~ s/\n.*//s;
        print "        Error: $err\n";
        $all_pass = 0;
    } else {
        print "  PASS: MyApi loaded successfully\n";
    }
} else {
    print "  SKIP: MyApi.pm not found (ok if testing framework only)\n";
}
print "\n";

# Test 6: JSON encode/decode
print "Test 6: JSON Functionality\n";
print "-" x 50, "\n";
eval {
    require JSON;
    my $data = { test => 'value', num => 123 };
    my $json = JSON::encode_json($data);
    my $decoded = JSON::decode_json($json);
    if ($decoded->{test} eq 'value' && $decoded->{num} == 123) {
        print "  PASS: JSON encode/decode works correctly\n";
    } else {
        print "  FAIL: JSON encode/decode returned wrong values\n";
        $all_pass = 0;
    }
};
if ($@) {
    print "  FAIL: JSON test error: $@\n";
    $all_pass = 0;
}
print "\n";

# Test 7: SHA256
print "Test 7: SHA256 Hashing\n";
print "-" x 50, "\n";
eval {
    require Digest::SHA;
    my $hash = Digest::SHA::sha256_hex('test');
    if (length($hash) == 64 && $hash =~ /^[a-f0-9]+$/) {
        print "  PASS: SHA256 hashing works\n";
    } else {
        print "  FAIL: SHA256 returned invalid hash\n";
        $all_pass = 0;
    }
};
if ($@) {
    print "  FAIL: SHA256 test error: $@\n";
    $all_pass = 0;
}
print "\n";

# Test 8: /dev/urandom (for token generation)
print "Test 8: Random Number Source\n";
print "-" x 50, "\n";
if (-r '/dev/urandom') {
    print "  PASS: /dev/urandom available (secure tokens)\n";
} else {
    print "  WARN: /dev/urandom not available\n";
    print "        (will use fallback - less secure but functional)\n";
}
print "\n";

# Test 9: File permissions
print "Test 9: File Permissions\n";
print "-" x 50, "\n";
if (-f 'api.cgi') {
    if (-x 'api.cgi') {
        print "  PASS: api.cgi is executable\n";
    } else {
        print "  FAIL: api.cgi is not executable\n";
        print "        Run: chmod 755 api.cgi\n";
        $all_pass = 0;
    }
} else {
    print "  SKIP: api.cgi not found\n";
}
print "\n";

# Summary
print "=" x 60, "\n";
if ($all_pass) {
    print "ALL TESTS PASSED!\n\n";
    print "Next steps:\n";
    print "  1. Edit MyApi.pm with your database credentials\n";
    print "  2. Run: mysql < schema.sql\n";
    print "  3. Run: perl create_user.pl demo demo123\n";
    print "  4. Test: curl http://yoursite.com/path/\n";
} else {
    print "SOME TESTS FAILED\n\n";
    print "Fix the issues above before deploying.\n";
}
print "=" x 60, "\n";
