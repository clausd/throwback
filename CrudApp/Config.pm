package CrudApp::Config;
use strict;
use warnings;

#############################################################################
# CrudApp Configuration Loader
#
# Loads configuration from (in priority order):
# 1. Environment variables (CRUDAPP_*)
# 2. Config file (crudapp.conf or .crudapp.conf)
#
# Usage:
#   my $config = CrudApp::Config->load('crudapp.conf');
#   my $db_type = $config->{database}{type};
#############################################################################

sub load {
    my ($class, $file) = @_;

    my $config = {};

    # Priority 2: Config file (load first, env vars override)
    if ($file && -f $file) {
        $config = _load_from_file($file, $config);
    } elsif (-f 'crudapp.conf') {
        $config = _load_from_file('crudapp.conf', $config);
    } elsif (-f '.crudapp.conf') {
        $config = _load_from_file('.crudapp.conf', $config);
    }

    # Priority 1: Environment variables (override file settings)
    $config = _load_from_env($config);

    return $config;
}

sub _load_from_env {
    my ($config) = @_;

    # Database settings
    $config->{database}{type} = $ENV{CRUDAPP_DB_TYPE} if $ENV{CRUDAPP_DB_TYPE};
    $config->{database}{path} = $ENV{CRUDAPP_DB_PATH} if $ENV{CRUDAPP_DB_PATH};
    $config->{database}{name} = $ENV{CRUDAPP_DB_NAME} if $ENV{CRUDAPP_DB_NAME};
    $config->{database}{user} = $ENV{CRUDAPP_DB_USER} if $ENV{CRUDAPP_DB_USER};
    $config->{database}{pass} = $ENV{CRUDAPP_DB_PASS} if $ENV{CRUDAPP_DB_PASS};
    $config->{database}{host} = $ENV{CRUDAPP_DB_HOST} if $ENV{CRUDAPP_DB_HOST};

    # Server settings
    $config->{server}{port}       = $ENV{CRUDAPP_PORT}       if $ENV{CRUDAPP_PORT};
    $config->{server}{host}       = $ENV{CRUDAPP_HOST}       if $ENV{CRUDAPP_HOST};
    $config->{server}{static_dir} = $ENV{CRUDAPP_STATIC_DIR} if $ENV{CRUDAPP_STATIC_DIR};
    $config->{server}{app_url}    = $ENV{CRUDAPP_APP_URL}    if $ENV{CRUDAPP_APP_URL};

    # SMTP settings
    $config->{smtp}{host}      = $ENV{CRUDAPP_SMTP_HOST}      if $ENV{CRUDAPP_SMTP_HOST};
    $config->{smtp}{port}      = $ENV{CRUDAPP_SMTP_PORT}      if $ENV{CRUDAPP_SMTP_PORT};
    $config->{smtp}{user}      = $ENV{CRUDAPP_SMTP_USER}      if $ENV{CRUDAPP_SMTP_USER};
    $config->{smtp}{pass}      = $ENV{CRUDAPP_SMTP_PASS}      if $ENV{CRUDAPP_SMTP_PASS};
    $config->{smtp}{from}      = $ENV{CRUDAPP_SMTP_FROM}      if $ENV{CRUDAPP_SMTP_FROM};
    $config->{smtp}{from_name} = $ENV{CRUDAPP_SMTP_FROM_NAME} if $ENV{CRUDAPP_SMTP_FROM_NAME};
    $config->{smtp}{ssl}       = $ENV{CRUDAPP_SMTP_SSL}       if $ENV{CRUDAPP_SMTP_SSL};
    $config->{smtp}{starttls}  = $ENV{CRUDAPP_SMTP_STARTTLS}  if $ENV{CRUDAPP_SMTP_STARTTLS};

    return $config;
}

sub _load_from_file {
    my ($file, $config) = @_;

    open my $fh, '<', $file or return $config;

    my $section = 'default';
    while (<$fh>) {
        chomp;
        s/^\s+//; s/\s+$//;  # Trim whitespace
        next if /^#/ || /^;/ || /^$/;  # Skip comments and blank lines

        if (/^\[(\w+)\]$/) {
            $section = $1;
            next;
        }

        if (/^(\w+)\s*=\s*(.*)$/) {
            my ($key, $val) = ($1, $2);
            $val =~ s/^["']|["']$//g;  # Remove surrounding quotes
            $val =~ s/\s+#.*$//;       # Remove inline comments
            $config->{$section}{$key} = $val;
        }
    }
    close $fh;

    return $config;
}

1;

__END__

=head1 NAME

CrudApp::Config - Configuration loader for CrudApp

=head1 SYNOPSIS

    use CrudApp::Config;

    my $config = CrudApp::Config->load('crudapp.conf');

    # Access database settings
    my $db_type = $config->{database}{type};  # 'mysql' or 'sqlite'
    my $db_path = $config->{database}{path};  # SQLite file path

    # Access server settings
    my $port = $config->{server}{port};

=head1 CONFIGURATION FILE FORMAT

    # crudapp.conf
    [database]
    type = sqlite
    path = ./dev.db

    # For MySQL:
    # type = mysql
    # name = mydb
    # user = root
    # pass = secret
    # host = localhost

    [server]
    port = 3000
    host = 127.0.0.1
    static_dir = ./example

=head1 ENVIRONMENT VARIABLES

    CRUDAPP_DB_TYPE    - Database type (mysql or sqlite)
    CRUDAPP_DB_PATH    - SQLite database file path
    CRUDAPP_DB_NAME    - MySQL database name
    CRUDAPP_DB_USER    - MySQL username
    CRUDAPP_DB_PASS    - MySQL password
    CRUDAPP_DB_HOST    - MySQL host (default: localhost)
    CRUDAPP_PORT       - Server port (default: 3000)
    CRUDAPP_HOST       - Server bind address
    CRUDAPP_STATIC_DIR - Static files directory

=cut
