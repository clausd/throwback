#!/usr/bin/perl
#
# CrudApp API Entry Point
#
# This is the CGI script that handles all API requests.
# Apache routes requests here via .htaccess rewrite rules.
#
use strict;
use warnings;
use lib '.', '..';
use MyApi;

MyApi->new->run;
