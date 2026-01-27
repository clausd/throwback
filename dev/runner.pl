#!/usr/bin/perl
#
# CrudApp Local Development Server
#
# Usage:
#   perl dev/runner.pl                         # Start with defaults
#   perl dev/runner.pl --port 8080             # Custom port
#   perl dev/runner.pl --config myapp.conf     # Custom config
#

use strict;
use warnings;
use File::Basename;
use File::Spec;
use Getopt::Long;

# Find our location and set up paths
my $base_dir;
BEGIN {
    my $script_dir = dirname(File::Spec->rel2abs(__FILE__));
    $base_dir = dirname($script_dir);
    chdir $base_dir or die "Cannot chdir to $base_dir: $!";
    unshift @INC, $base_dir;
}

use CrudApp::Config;
use CrudApp::DB;
use CrudApp::DevServer;

# Default configuration
my $port = 3000;
my $host = '127.0.0.1';
my $config_file = 'crudapp.conf';
my $static_dir = './example';
my $api_module = 'MyApi';
my $help = 0;

GetOptions(
    'port=i'   => \$port,
    'host=s'   => \$host,
    'config=s' => \$config_file,
    'static=s' => \$static_dir,
    'api=s'    => \$api_module,
    'help|h'   => \$help,
) or die "Error in command line arguments\n";

if ($help) {
    print <<'USAGE';
CrudApp Local Development Server

Usage: perl dev/runner.pl [OPTIONS]

Options:
  --port PORT     Server port (default: 3000)
  --host HOST     Bind address (default: 127.0.0.1)
  --config FILE   Configuration file (default: crudapp.conf)
  --static DIR    Static files directory (default: ./example)
  --api MODULE    API module to load (default: MyApi)
  --help, -h      Show this help message

Examples:
  perl dev/runner.pl
  perl dev/runner.pl --port 8080
  perl dev/runner.pl --static ./myapp --api MyApp

USAGE
    exit 0;
}

# Load configuration
my $config = CrudApp::Config->load($config_file);

# Config values as defaults, command-line overrides
$port       = $config->{server}{port}       if $config->{server}{port} && !grep { /--port/ } @ARGV;
$host       = $config->{server}{host}       if $config->{server}{host} && !grep { /--host/ } @ARGV;
$static_dir = $config->{server}{static_dir} if $config->{server}{static_dir} && !grep { /--static/ } @ARGV;

# Add static dir to lib path for finding the API module
push @INC, $static_dir if -d $static_dir;

# Load the API module
{
    my $module_file = "$static_dir/$api_module.pm";
    if (-f $module_file) {
        require $module_file;
    } else {
        eval "require $api_module"
            or die "Cannot load API module '$api_module': $@\n"
                 . "Make sure $api_module.pm exists in $static_dir or \@INC\n";
    }
}

# Create database adapter
my $db_adapter;
if ($config->{database} && $config->{database}{type}) {
    $db_adapter = CrudApp::DB->new($config->{database});
}

# Start the dev server
CrudApp::DevServer::start({
    host        => $host,
    port        => $port,
    static_dir  => $static_dir,
    api_module  => $api_module,
    db_adapter  => $db_adapter,
    config_file => $config_file,
    db_type     => $config->{database}{type} || 'mysql',
    db_path     => $config->{database}{path} || '',
});
