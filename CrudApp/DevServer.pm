package CrudApp::DevServer;
use strict;
use warnings;
use HTTP::Daemon;
use HTTP::Response;
use File::Spec;
use CGI;

my %MIME_TYPES = (
    html => 'text/html; charset=utf-8',
    htm  => 'text/html; charset=utf-8',
    css  => 'text/css; charset=utf-8',
    js   => 'application/javascript; charset=utf-8',
    mjs  => 'application/javascript; charset=utf-8',
    json => 'application/json; charset=utf-8',
    png  => 'image/png',
    jpg  => 'image/jpeg',
    jpeg => 'image/jpeg',
    gif  => 'image/gif',
    svg  => 'image/svg+xml',
    ico  => 'image/x-icon',
    woff => 'font/woff',
    woff2=> 'font/woff2',
    ttf  => 'font/ttf',
    eot  => 'application/vnd.ms-fontobject',
    map  => 'application/json',
    txt  => 'text/plain; charset=utf-8',
    xml  => 'application/xml',
);

# start(\%opts)
#
# Options:
#   host        - bind address (default 127.0.0.1)
#   port        - port (default 3000)
#   static_dir  - directory for static files
#   api_module  - Perl module name (must already be loaded)
#   db_adapter  - CrudApp::DB::* adapter instance (or undef)
#   config_file - config file path (for display only)
sub start {
    my ($opts) = @_;

    my $host        = $opts->{host} || '127.0.0.1';
    my $port        = $opts->{port} || 3000;
    my $static_dir  = $opts->{static_dir} || '.';
    my $api_module  = $opts->{api_module} || die "api_module required\n";
    my $db_adapter  = $opts->{db_adapter};
    my $config_file = $opts->{config_file} || 'crudapp.conf';
    my $db_type     = $opts->{db_type} || 'sqlite';
    my $db_path     = $opts->{db_path} || '';

    my $daemon = HTTP::Daemon->new(
        LocalAddr => $host,
        LocalPort => $port,
        ReuseAddr => 1,
        Listen    => 10,
    ) or die "Cannot create HTTP server on $host:$port: $!\n";

    print "\n";
    print "=" x 60, "\n";
    print "  CrudApp Local Development Server\n";
    print "=" x 60, "\n";
    print "  URL:       http://$host:$port/\n";
    print "  Static:    $static_dir\n";
    print "  API:       $api_module\n";
    print "  Config:    $config_file\n";
    print "  Database:  $db_type\n";
    print "  DB Path:   $db_path\n" if $db_type eq 'sqlite' && $db_path;
    print "=" x 60, "\n";
    print "  Press Ctrl+C to stop\n";
    print "=" x 60, "\n\n";

    while (1) {
        my $conn = $daemon->accept or next;

        while (my $request = $conn->get_request) {
            eval { _handle_request($conn, $request, $static_dir, $api_module, $db_adapter, $host, $port) };
            if ($@) {
                warn "Error handling request: $@\n";
                my $r = HTTP::Response->new(500);
                $r->header('Content-Type' => 'application/json');
                $r->content('{"error":"Internal server error"}');
                $conn->send_response($r);
            }
        }

        $conn->close;
        undef $conn;
    }
}

sub _handle_request {
    my ($conn, $request, $static_dir, $api_module, $db_adapter, $host, $port) = @_;

    my $method = $request->method;
    my $uri    = $request->uri;
    my $path   = $uri->path;

    my $timestamp = localtime();
    print "[$timestamp] $method $path\n";

    $path =~ s|//+|/|g;
    $path =~ s|\.\./||g;

    # Static file
    my $static_file = File::Spec->catfile($static_dir, $path eq '/' ? 'index.html' : $path);

    if (-f $static_file) {
        _serve_static($conn, $static_file);
        return;
    }

    if (-d $static_file) {
        my $index = File::Spec->catfile($static_file, 'index.html');
        if (-f $index) {
            _serve_static($conn, $index);
            return;
        }
    }

    # API request
    _handle_api($conn, $request, $api_module, $db_adapter, $host, $port);
}

sub _serve_static {
    my ($conn, $file) = @_;

    my ($ext) = $file =~ /\.(\w+)$/;
    my $mime = $MIME_TYPES{lc($ext // '')} || 'application/octet-stream';

    open my $fh, '<:raw', $file or do {
        my $r = HTTP::Response->new(404);
        $r->content("File not found");
        $conn->send_response($r);
        return;
    };
    local $/;
    my $content = <$fh>;
    close $fh;

    my $r = HTTP::Response->new(200);
    $r->header('Content-Type' => $mime);
    $r->header('Content-Length' => length($content));
    $r->header('Cache-Control' => 'no-cache');
    $r->content($content);
    $conn->send_response($r);
}

sub _handle_api {
    my ($conn, $request, $api_module, $db_adapter, $host, $port) = @_;

    my $uri  = $request->uri;
    my $path = $uri->path;

    local %ENV = %ENV;

    $ENV{REQUEST_METHOD}     = $request->method;
    $ENV{PATH_INFO}          = $path;
    $ENV{QUERY_STRING}       = $uri->query // '';
    $ENV{CONTENT_TYPE}       = $request->header('Content-Type') // '';
    $ENV{CONTENT_LENGTH}     = length($request->content // '');
    $ENV{HTTP_AUTHORIZATION} = $request->header('Authorization') // '';
    $ENV{HTTP_HOST}          = "$host:$port";
    $ENV{SERVER_NAME}        = $host;
    $ENV{SERVER_PORT}        = $port;
    $ENV{SERVER_PROTOCOL}    = 'HTTP/1.1';
    $ENV{GATEWAY_INTERFACE}  = 'CGI/1.1';
    $ENV{SCRIPT_NAME}        = '/api.cgi';
    $ENV{REMOTE_ADDR}        = $conn->peerhost // '127.0.0.1';

    for my $header ($request->header_field_names) {
        my $env_name = 'HTTP_' . uc($header);
        $env_name =~ s/-/_/g;
        $ENV{$env_name} = $request->header($header);
    }

    my $body = $request->content // '';

    my $app;
    my $output = '';

    {
        open my $stdin, '<', \$body;
        local *STDIN = $stdin;

        open my $stdout, '>', \$output;
        local *STDOUT = $stdout;

        eval {
            $app = $api_module->new;
            $app->{_devserver} = 1;

            if ($db_adapter) {
                $app->set_db_adapter($db_adapter);
            }

            CGI::initialize_globals();
            $app->{_cgi} = CGI->new;

            # Run configure() so subclasses can set up SMTP, app_url, etc.
            # configure() should guard against re-initialising the DB when
            # _db_adapter was already set by the DevServer above.
            $app->configure;

            $app->_dispatch;
        };
    }
    # STDIN/STDOUT restored by local scope exit

    if ($@) {
        my $error = $@;
        $error =~ s/ at .* line \d+.*//s;
        warn "API Error: $error\n";

        my $r = HTTP::Response->new(500);
        $r->header('Content-Type' => 'application/json');
        $r->header('Access-Control-Allow-Origin' => '*');
        $r->content(qq({"error":"Internal server error: $error"}));
        $conn->send_response($r);
        return;
    }

    # Proxy: execute deferred HTTP request with real STDOUT restored
    if ($app && $app->{_proxy_request}) {
        my $pr = $app->{_proxy_request};
        require HTTP::Tiny;
        my $http     = HTTP::Tiny->new(timeout => 120);
        my $response = $http->request($pr->{method}, $pr->{url}, $pr->{options});

        my $r = HTTP::Response->new($response->{status});
        $r->header('Content-Type' => $response->{headers}{'content-type'} || 'application/json');
        $r->header('Access-Control-Allow-Origin' => '*');
        $r->header('Access-Control-Allow-Methods' => 'GET, POST, PUT, DELETE, OPTIONS');
        $r->header('Access-Control-Allow-Headers' => 'Content-Type, Authorization');
        $r->content($response->{content} // '');
        $conn->send_response($r);
        return;
    }

    my ($headers_text, $body_out) = split /\r?\n\r?\n/, $output, 2;
    $body_out //= '';

    my $status = 200;
    my %resp_headers;

    for my $line (split /\r?\n/, $headers_text // '') {
        if ($line =~ /^Status:\s*(\d+)/i) {
            $status = $1;
        } elsif ($line =~ /^([^:]+):\s*(.*)$/) {
            $resp_headers{$1} = $2;
        }
    }

    my $r = HTTP::Response->new($status);
    for my $key (keys %resp_headers) {
        $r->header($key => $resp_headers{$key});
    }

    $r->header('Access-Control-Allow-Origin' => '*');
    $r->header('Access-Control-Allow-Methods' => 'GET, POST, PUT, DELETE, OPTIONS');
    $r->header('Access-Control-Allow-Headers' => 'Content-Type, Authorization');

    $r->content($body_out);
    $conn->send_response($r);
}

1;
