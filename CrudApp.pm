package CrudApp;
use strict;
use warnings;

our $VERSION = '1.0.0';

# Minimal dependencies - all standard or widely available
use CGI;
use DBI;
use JSON;
use Digest::SHA qw(sha256_hex);

#############################################################################
# Constructor and Setup
#############################################################################

sub new {
    my $class = shift;
    bless {
        _class => $class,
        _cgi => undef,
        _dbh => undef,
        _json_input => undef,
        # Note: _current_user is NOT initialized here - we use 'exists' check
        _sent_headers => 0,
        _sent_body => 0,
    }, $class;
}

sub run {
    my $app = shift;
    $app->_setup;
    $app->_dispatch;
}

sub _setup {
    my $app = shift;
    $app->{_cgi} = CGI->new;
    $app->configure;
}

# Override in subclass to set database connection
sub configure {
    my $app = shift;
    # Subclass should call: $app->set_db('database', 'user', 'password');
}

sub set_db {
    my ($app, $db, $user, $pass, $host) = @_;
    $host ||= 'localhost';
    $app->{_dbh} = DBI->connect(
        "dbi:mysql:database=$db;host=$host",
        $user, $pass,
        { RaiseError => 1, PrintError => 0, mysql_enable_utf8 => 1 }
    );
}

#############################################################################
# Request Handling
#############################################################################

sub cgi { shift->{_cgi} }
sub dbh { shift->{_dbh} }

sub request_method {
    my $app = shift;
    return $ENV{REQUEST_METHOD} || 'GET';
}

sub path_info {
    my $app = shift;
    my $path = $ENV{PATH_INFO} || '/';
    $path =~ s|^/+|/|;  # normalize leading slashes
    return $path;
}

sub _parse_path {
    my $app = shift;
    my $path = $app->path_info;
    $path =~ s|^/||;
    $path =~ s|\.html$||i;

    my ($action, $id) = split('/', $path, 2);
    $action ||= 'index';

    return ($action, $id);
}

sub json_input {
    my $app = shift;
    return $app->{_json_input} if defined $app->{_json_input};

    my $raw = $app->cgi->param('POSTDATA')
           || $app->cgi->param('PUTDATA')
           || '';

    # Try reading from STDIN if no POSTDATA
    if (!$raw && $ENV{CONTENT_TYPE} && $ENV{CONTENT_TYPE} =~ /application\/json/i) {
        local $/;
        $raw = <STDIN> || '';
    }

    if ($raw) {
        eval { $app->{_json_input} = decode_json($raw); };
        $app->{_json_input} = undef if $@;
    }

    return $app->{_json_input};
}

sub param {
    my ($app, $name, $default) = @_;
    my $val = $app->cgi->param($name);
    return defined $val ? $val : $default;
}

sub param_int {
    my ($app, $name, $default) = @_;
    my $val = $app->param($name, $default);
    return ($val && $val =~ /^-?\d+$/) ? int($val) : $default;
}

#############################################################################
# Routing and Dispatch
#############################################################################

sub _dispatch {
    my $app = shift;
    my ($action, $id) = $app->_parse_path;

    $app->{_path_id} = $id;

    my $class = $app->{_class};
    my $method = $class->can($action);

    unless ($method) {
        return $app->render_error("Not found: $action", 404);
    }

    eval { $method->($app); };

    if ($@) {
        my $err = $@;
        $err =~ s/ at .* line \d+.*//s;  # Clean up error for display
        $app->render_error("Internal error: $err", 500);
    }
}

sub path_id {
    my $app = shift;
    return $app->{_path_id};
}

#############################################################################
# Response Rendering
#############################################################################

sub render_json {
    my ($app, $data, $status) = @_;
    $status ||= 200;

    return if $app->{_sent_body};

    print $app->cgi->header(
        -type => 'application/json',
        -charset => 'utf-8',
        -status => $status
    );
    print encode_json($data);

    $app->{_sent_headers} = 1;
    $app->{_sent_body} = 1;
}

sub render_error {
    my ($app, $message, $status) = @_;
    $status ||= 400;
    $app->render_json({ error => $message }, $status);
}

#############################################################################
# Default Routes
#############################################################################

sub index {
    my $app = shift;
    $app->render_json({
        status => 'ok',
        message => 'CrudApp API',
        version => $VERSION
    });
}

#############################################################################
# Authentication
#############################################################################

sub generate_token {
    my $app = shift;
    my $random = '';

    if (open my $fh, '<', '/dev/urandom') {
        read $fh, $random, 32;
        close $fh;
    } else {
        $random = time() . $$ . rand() . rand();
    }

    return sha256_hex($random);
}

sub login {
    my $app = shift;
    my $input = $app->json_input;

    return $app->render_error("Missing credentials", 400)
        unless $input && $input->{username} && $input->{password};

    # Fetch user
    my $user = $app->get_row('_auth', { username => $input->{username} });
    return $app->render_error("Invalid credentials", 401) unless $user;

    # Verify password
    my $hash = sha256_hex($user->{password_salt} . $input->{password});
    return $app->render_error("Invalid credentials", 401)
        unless $hash eq $user->{password_hash};

    # Create session
    my $token = $app->generate_token;
    my $expires = time() + (86400 * 7);  # 7 days

    $app->dbh->do(
        "INSERT INTO _sessions (token, user_id, expires_at) VALUES (?, ?, FROM_UNIXTIME(?))",
        undef, $token, $user->{id}, $expires
    );

    $app->render_json({ token => $token, expires => $expires });
}

sub logout {
    my $app = shift;
    my $token = $app->_get_bearer_token;

    if ($token) {
        $app->dbh->do("DELETE FROM _sessions WHERE token = ?", undef, $token);
    }

    $app->render_json({ ok => 1 });
}

sub _get_bearer_token {
    my $app = shift;
    my $auth = $ENV{HTTP_AUTHORIZATION} || '';
    my ($token) = $auth =~ /^Bearer\s+(\S+)/i;
    return $token;
}

sub current_user {
    my $app = shift;
    return $app->{_current_user} if exists $app->{_current_user};

    my $token = $app->_get_bearer_token;
    return $app->{_current_user} = undef unless $token;

    my $row = $app->dbh->selectrow_hashref(
        "SELECT u.* FROM _auth u
         JOIN _sessions s ON s.user_id = u.id
         WHERE s.token = ? AND s.expires_at > NOW()",
        undef, $token
    );

    if ($row) {
        $row->{_access} = eval { decode_json($row->{access_rules} || '{}') } || {};
        $app->{_current_user} = $row;
    }

    return $app->{_current_user};
}

#############################################################################
# Access Control
#############################################################################

# Override in subclass to allow anonymous access
# Return: { table_name => ['read'], other_table => ['read', 'create'] }
sub anon_access {
    return {};
}

sub check_access {
    my ($app, $table, $operation) = @_;

    # Check anonymous access first
    my $anon = $app->anon_access;
    if ($anon->{$table}) {
        return 1 if grep { $_ eq $operation || $_ eq '*' } @{$anon->{$table}};
    }

    # Must be authenticated for non-anonymous access
    my $user = $app->current_user;
    return 0 unless $user;

    my $rules = $user->{_access}{tables} || {};

    # Check specific table, then wildcard
    for my $key ($table, '*') {
        next unless $rules->{$key};
        my $allowed = $rules->{$key}{access} || [];
        return 1 if grep { $_ eq $operation || $_ eq '*' } @$allowed;
    }

    return 0;
}

sub get_filters {
    my ($app, $table) = @_;
    my $user = $app->current_user;
    return {} unless $user;

    my $rules = $user->{_access}{tables}{$table} || {};
    my $filters = $rules->{filters} || {};
    my %resolved;

    for my $key (keys %$filters) {
        my $val = $filters->{$key};
        if ($val eq '$user.id') {
            $resolved{$key} = $user->{id};
        } elsif ($val =~ /^\$user\.(\w+)$/) {
            $resolved{$key} = $user->{$1};
        } else {
            $resolved{$key} = $val;
        }
    }

    return \%resolved;
}

#############################################################################
# CRUD Operations
#############################################################################

sub crud {
    my ($app, $table) = @_;

    # Private tables (starting with _) are never accessible
    if ($table =~ /^_/) {
        return $app->render_error("Access denied", 403);
    }

    my $method = $app->request_method;
    my $operation = $method eq 'DELETE' ? 'delete'
                  : $method eq 'POST'   ? ($app->json_input && $app->json_input->{id} ? 'update' : 'create')
                  : 'read';

    unless ($app->check_access($table, $operation)) {
        return $app->render_error("Unauthorized", 401);
    }

    if ($method eq 'GET') {
        $app->_crud_read($table);
    } elsif ($method eq 'POST') {
        $app->_crud_upsert($table);
    } elsif ($method eq 'DELETE') {
        $app->_crud_delete($table);
    } else {
        $app->render_error("Method not allowed", 405);
    }
}

sub _crud_read {
    my ($app, $table) = @_;
    my $filters = $app->get_filters($table);
    my $id = $app->path_id;

    if ($id) {
        $filters->{id} = $id;
        my $row = $app->get_row($table, $filters);
        return $row
            ? $app->render_json($row)
            : $app->render_error("Not found", 404);
    }

    # List with pagination
    my $limit = $app->param_int('limit', 20);
    my $offset = $app->param_int('offset', 0);
    $limit = 100 if $limit > 100;

    my $rows = $app->get_rows($table, $filters, $limit, $offset);
    $app->render_json({
        data => $rows,
        limit => $limit,
        offset => $offset
    });
}

sub _crud_upsert {
    my ($app, $table) = @_;
    my $input = $app->json_input;
    return $app->render_error("Invalid JSON body", 400) unless $input;

    my $filters = $app->get_filters($table);

    # Apply required filters to input
    for my $key (keys %$filters) {
        $input->{$key} = $filters->{$key};
    }

    if ($input->{id}) {
        # Update - verify ownership
        my $existing = $app->get_row($table, { id => $input->{id}, %$filters });
        return $app->render_error("Not found", 404) unless $existing;

        $app->update_row($table, $input->{id}, $input);
        my $updated = $app->get_row($table, { id => $input->{id} });
        $app->render_json($updated, 200);
    } else {
        # Create
        my $id = $app->insert_row($table, $input);
        my $created = $app->get_row($table, { id => $id });
        $app->render_json($created, 201);
    }
}

sub _crud_delete {
    my ($app, $table) = @_;
    my $id = $app->path_id;
    return $app->render_error("ID required", 400) unless $id;

    my $filters = $app->get_filters($table);
    $filters->{id} = $id;

    my $deleted = $app->delete_row($table, $filters);

    $deleted
        ? $app->render_json({ deleted => $id })
        : $app->render_error("Not found", 404);
}

#############################################################################
# Simple Database Helpers (replaces DBIx::Abstract)
#############################################################################

# Get column types for a table (cached)
sub _get_column_types {
    my ($app, $table) = @_;

    $app->{_column_types} ||= {};
    return $app->{_column_types}{$table} if $app->{_column_types}{$table};

    my $sth = $app->dbh->column_info(undef, undef, $table, '%');
    my %types;

    while (my $col = $sth->fetchrow_hashref) {
        my $type = uc($col->{TYPE_NAME} || '');
        # Mark numeric types
        $types{$col->{COLUMN_NAME}} = 'numeric'
            if $type =~ /^(INT|INTEGER|TINYINT|SMALLINT|MEDIUMINT|BIGINT|FLOAT|DOUBLE|DECIMAL|NUMERIC|REAL)/;
    }

    $app->{_column_types}{$table} = \%types;
    return \%types;
}

# Convert numeric columns to actual numbers for proper JSON encoding
# Uses schema information rather than guessing from values
sub _fix_types {
    my ($app, $row, $table) = @_;
    return unless $row && ref $row eq 'HASH';

    my $types = $app->_get_column_types($table);

    for my $key (keys %$row) {
        next unless defined $row->{$key};
        next unless $types->{$key} && $types->{$key} eq 'numeric';
        $row->{$key} = $row->{$key} + 0;  # Convert to number
    }
    return $row;
}

sub get_row {
    my ($app, $table, $where) = @_;
    $where ||= {};

    my @cols = keys %$where;
    my $sql = "SELECT * FROM `$table`";
    $sql .= " WHERE " . join(' AND ', map { "`$_` = ?" } @cols) if @cols;
    $sql .= " LIMIT 1";

    my $row = $app->dbh->selectrow_hashref($sql, undef, map { $where->{$_} } @cols);
    return $app->_fix_types($row, $table);
}

sub get_rows {
    my ($app, $table, $where, $limit, $offset) = @_;
    $where ||= {};
    $limit ||= 20;
    $offset ||= 0;

    my @cols = keys %$where;
    my $sql = "SELECT * FROM `$table`";
    $sql .= " WHERE " . join(' AND ', map { "`$_` = ?" } @cols) if @cols;
    $sql .= " LIMIT ? OFFSET ?";

    my @vals = (map { $where->{$_} } @cols);
    push @vals, $limit, $offset;

    my $rows = $app->dbh->selectall_arrayref($sql, { Slice => {} }, @vals);
    $app->_fix_types($_, $table) for @$rows;
    return $rows;
}

sub insert_row {
    my ($app, $table, $data) = @_;

    my @cols = keys %$data;
    my $sql = "INSERT INTO `$table` (" . join(', ', map { "`$_`" } @cols) . ") "
            . "VALUES (" . join(', ', map { '?' } @cols) . ")";

    $app->dbh->do($sql, undef, map { $data->{$_} } @cols);
    return $app->dbh->last_insert_id(undef, undef, $table, undef);
}

sub update_row {
    my ($app, $table, $id, $data) = @_;

    # Remove id from data to update
    my %update = %$data;
    delete $update{id};

    my @cols = keys %update;
    return unless @cols;

    my $sql = "UPDATE `$table` SET "
            . join(', ', map { "`$_` = ?" } @cols)
            . " WHERE id = ?";

    return $app->dbh->do($sql, undef, (map { $update{$_} } @cols), $id);
}

sub delete_row {
    my ($app, $table, $where) = @_;

    my @cols = keys %$where;
    my $sql = "DELETE FROM `$table` WHERE "
            . join(' AND ', map { "`$_` = ?" } @cols);

    my $rows = $app->dbh->do($sql, undef, map { $where->{$_} } @cols);
    return $rows && $rows > 0;
}

#############################################################################
# Custom Query Methods (for joins, complex queries, etc.)
#############################################################################

sub query_row {
    my ($app, $sql, @params) = @_;
    return $app->dbh->selectrow_hashref($sql, undef, @params);
}

sub query_rows {
    my ($app, $sql, @params) = @_;
    return $app->dbh->selectall_arrayref($sql, { Slice => {} }, @params);
}

sub query_value {
    my ($app, $sql, @params) = @_;
    my ($value) = $app->dbh->selectrow_array($sql, undef, @params);
    return $value;
}

sub query_column {
    my ($app, $sql, @params) = @_;
    return $app->dbh->selectcol_arrayref($sql, undef, @params);
}

sub query_do {
    my ($app, $sql, @params) = @_;
    return $app->dbh->do($sql, undef, @params);
}

#############################################################################
# User Management (for setup scripts)
#############################################################################

sub create_user {
    my ($app, $username, $password, $access_rules) = @_;

    my $salt = substr($app->generate_token, 0, 32);
    my $hash = sha256_hex($salt . $password);

    $app->dbh->do(
        "INSERT INTO _auth (username, password_salt, password_hash, access_rules) VALUES (?, ?, ?, ?)",
        undef, $username, $salt, $hash, encode_json($access_rules || {})
    );

    return $app->dbh->last_insert_id(undef, undef, '_auth', undef);
}

1;

__END__

=head1 NAME

CrudApp - Minimal JSON API framework for Perl CGI

=head1 VERSION

Version 1.0.0

=head1 SYNOPSIS

    # MyApi.pm
    package MyApi;
    use strict;
    use base 'CrudApp';

    sub configure {
        my $app = shift;
        $app->set_db('mydb', 'user', 'password');
    }

    # Allow anonymous read access to posts
    sub anon_access {
        return { posts => ['read'] };
    }

    # Expose tables via CRUD
    sub posts { shift->crud('posts') }
    sub todos { shift->crud('todos') }

    1;

    # api.cgi
    #!/usr/bin/perl
    use strict;
    use MyApi;
    MyApi->new->run;

=head1 DESCRIPTION

CrudApp is a minimal JSON API framework designed for maximum compatibility
with shared hosting environments. It has only standard Perl dependencies:

=over 4

=item * CGI (core module)

=item * DBI (standard)

=item * JSON (widely available)

=item * Digest::SHA (core since 5.10)

=back

=head1 FEATURES

=over 4

=item * Token-based authentication

=item * Per-user access control with row-level filters

=item * Automatic CRUD for database tables

=item * Clean JSON API responses

=item * No external dependencies beyond standard modules

=back

=head1 DEPLOYMENT

CrudApp is designed for the B<static frontend + JSON API> pattern:

    Browser                     Apache
    ───────                     ──────
    GET /index.html  ────────►  Serves static file
    GET /app.js      ────────►  Serves static file

    POST /api/login  ────────►  Routes to api.cgi → JSON
    GET /api/todos   ────────►  Routes to api.cgi → JSON

Static files (HTML, CSS, JS) are served directly by Apache. Only API
requests hit the CGI script. See the example/ directory for a complete
deployment setup.

=head1 METHODS

=head2 Core Methods

=over 4

=item new()

Create a new application instance.

=item run()

Set up the application and dispatch the request.

=item configure()

Override in your subclass to set up the database connection:

    sub configure {
        my $app = shift;
        $app->set_db('database', 'user', 'password');
    }

=item set_db($database, $user, $password, $host)

Connect to MySQL database. Host defaults to 'localhost'.

=back

=head2 Request Methods

=over 4

=item cgi()

Returns the CGI object.

=item dbh()

Returns the DBI database handle.

=item request_method()

Returns the HTTP method (GET, POST, DELETE, etc.)

=item path_info()

Returns the request path.

=item path_id()

Returns the ID from the URL path (e.g., /todos/123 returns "123").

=item json_input()

Returns parsed JSON from the request body (for POST/PUT).

=item param($name, $default)

Get a query parameter with optional default.

=item param_int($name, $default)

Get an integer parameter with validation.

=back

=head2 Response Methods

=over 4

=item render_json($data, $status)

Output JSON response. Status defaults to 200.

=item render_error($message, $status)

Output JSON error response. Status defaults to 400.

=back

=head2 Authentication

=over 4

=item login()

Built-in login handler. POST /login with:

    {"username": "user", "password": "pass"}

Returns:

    {"token": "abc123...", "expires": 1234567890}

=item logout()

Built-in logout handler. Invalidates the current token.

=item current_user()

Returns the authenticated user record, or undef.

=item create_user($username, $password, $access_rules)

Create a user (for setup scripts, not API).

=back

=head2 Access Control

=over 4

=item anon_access()

Override to allow anonymous access to tables:

    sub anon_access {
        return {
            posts => ['read'],
            public => ['read', 'create']
        };
    }

=item check_access($table, $operation)

Check if current user can perform operation on table.

=item get_filters($table)

Get row-level filters for current user.

=back

=head2 CRUD

=over 4

=item crud($table)

Handle CRUD operations for a table. Call from your table method:

    sub todos { shift->crud('todos') }

Supports:

    GET /todos       - List records
    GET /todos/123   - Get single record
    POST /todos      - Create record (no id in body)
    POST /todos      - Update record (id in body)
    DELETE /todos/123 - Delete record

=back

=head2 Database Helpers

Simple DBI wrappers for basic single-table operations:

=over 4

=item get_row($table, \%where)

Get single row matching conditions.

    my $user = $app->get_row('users', { id => 123 });
    my $post = $app->get_row('posts', { slug => 'hello-world' });

=item get_rows($table, \%where, $limit, $offset)

Get multiple rows with pagination.

    my $rows = $app->get_rows('posts', { status => 'published' }, 10, 0);

=item insert_row($table, \%data)

Insert row, returns new ID.

    my $id = $app->insert_row('posts', {
        title => 'New Post',
        user_id => $user->{id}
    });

=item update_row($table, $id, \%data)

Update row by ID.

    $app->update_row('posts', $id, { title => 'Updated Title' });

=item delete_row($table, \%where)

Delete rows matching conditions.

    $app->delete_row('posts', { id => 123 });

=back

=head2 Custom Query Methods

For complex queries, joins, aggregations, or anything beyond simple
single-table operations, use these methods with raw SQL:

=over 4

=item query_row($sql, @params)

Execute query and return single row as hashref.

    # Join example: get todo with user info
    my $todo = $app->query_row(
        "SELECT t.*, u.username, u.email
         FROM todos t
         JOIN _auth u ON u.id = t.user_id
         WHERE t.id = ?",
        $todo_id
    );

    # Complex conditions
    my $post = $app->query_row(
        "SELECT * FROM posts
         WHERE status = ? AND published_at <= NOW()
         ORDER BY published_at DESC
         LIMIT 1",
        'published'
    );

=item query_rows($sql, @params)

Execute query and return all rows as arrayref of hashrefs.

    # Join with multiple tables
    my $comments = $app->query_rows(
        "SELECT c.*, u.username, p.title as post_title
         FROM comments c
         JOIN _auth u ON u.id = c.user_id
         JOIN posts p ON p.id = c.post_id
         WHERE p.id = ?
         ORDER BY c.created_at DESC",
        $post_id
    );

    # Aggregation
    my $stats = $app->query_rows(
        "SELECT user_id, COUNT(*) as todo_count,
                SUM(done) as completed_count
         FROM todos
         GROUP BY user_id
         HAVING todo_count > ?"
        5
    );

    # Search with LIKE
    my $results = $app->query_rows(
        "SELECT * FROM posts
         WHERE title LIKE ? OR body LIKE ?
         ORDER BY created_at DESC
         LIMIT ?",
        "%$search%", "%$search%", 20
    );

=item query_value($sql, @params)

Execute query and return single scalar value.

    # Count
    my $count = $app->query_value(
        "SELECT COUNT(*) FROM todos WHERE user_id = ? AND done = 0",
        $user_id
    );

    # Sum
    my $total = $app->query_value(
        "SELECT SUM(amount) FROM orders WHERE user_id = ?",
        $user_id
    );

    # Check existence
    my $exists = $app->query_value(
        "SELECT 1 FROM users WHERE email = ?",
        $email
    );

=item query_column($sql, @params)

Execute query and return single column as arrayref.

    # Get list of IDs
    my $ids = $app->query_column(
        "SELECT id FROM posts WHERE user_id = ?",
        $user_id
    );

    # Get unique values
    my $tags = $app->query_column(
        "SELECT DISTINCT tag FROM post_tags WHERE post_id = ?",
        $post_id
    );

=item query_do($sql, @params)

Execute non-SELECT query (INSERT, UPDATE, DELETE, etc.)

    # Bulk update
    $app->query_do(
        "UPDATE todos SET done = 1 WHERE user_id = ? AND due_date < NOW()",
        $user_id
    );

    # Delete with join condition
    $app->query_do(
        "DELETE c FROM comments c
         JOIN posts p ON p.id = c.post_id
         WHERE p.user_id = ?",
        $user_id
    );

    # Insert with subquery
    $app->query_do(
        "INSERT INTO notifications (user_id, message)
         SELECT user_id, ? FROM subscriptions WHERE topic = ?",
        $message, $topic
    );

=back

=head2 Custom Endpoint Examples

When the automatic C<crud()> method isn't enough, create custom endpoints:

    # Custom endpoint with join
    sub todos_with_users {
        my $app = shift;

        my $user = $app->current_user;
        return $app->render_error("Unauthorized", 401) unless $user;

        my $todos = $app->query_rows(
            "SELECT t.*, u.username
             FROM todos t
             JOIN _auth u ON u.id = t.user_id
             WHERE t.user_id = ?
             ORDER BY t.created_at DESC",
            $user->{id}
        );

        $app->render_json({ data => $todos });
    }

    # Dashboard with aggregated stats
    sub dashboard {
        my $app = shift;

        my $user = $app->current_user;
        return $app->render_error("Unauthorized", 401) unless $user;

        my $stats = {
            total_todos => $app->query_value(
                "SELECT COUNT(*) FROM todos WHERE user_id = ?",
                $user->{id}
            ),
            completed => $app->query_value(
                "SELECT COUNT(*) FROM todos WHERE user_id = ? AND done = 1",
                $user->{id}
            ),
            recent => $app->query_rows(
                "SELECT * FROM todos WHERE user_id = ?
                 ORDER BY created_at DESC LIMIT 5",
                $user->{id}
            )
        };

        $app->render_json($stats);
    }

    # Search across multiple tables
    sub search {
        my $app = shift;

        my $q = $app->param('q');
        return $app->render_error("Query required", 400) unless $q;

        my $pattern = "%$q%";

        my $results = {
            posts => $app->query_rows(
                "SELECT id, title FROM posts
                 WHERE title LIKE ? LIMIT 10",
                $pattern
            ),
            users => $app->query_rows(
                "SELECT id, username FROM _auth
                 WHERE username LIKE ? LIMIT 10",
                $pattern
            )
        };

        $app->render_json($results);
    }

=head1 ACCESS RULES

User access rules are stored as JSON in the _auth.access_rules column:

    {
        "tables": {
            "*": { "access": ["read"] },
            "todos": {
                "access": ["create", "read", "update", "delete"],
                "filters": { "user_id": "$user.id" }
            }
        }
    }

The filter C<"user_id": "$user.id"> means users can only see records
where user_id matches their own ID.

=head1 DATABASE SCHEMA

Required tables:

    CREATE TABLE _auth (
        id INT AUTO_INCREMENT PRIMARY KEY,
        username VARCHAR(255) UNIQUE NOT NULL,
        password_salt VARCHAR(32) NOT NULL,
        password_hash VARCHAR(64) NOT NULL,
        access_rules TEXT,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
    );

    CREATE TABLE _sessions (
        id INT AUTO_INCREMENT PRIMARY KEY,
        token VARCHAR(64) UNIQUE NOT NULL,
        user_id INT NOT NULL,
        expires_at TIMESTAMP NOT NULL,
        FOREIGN KEY (user_id) REFERENCES _auth(id) ON DELETE CASCADE
    );

=head1 EXAMPLE

See the example/ directory for a complete todo application.

=head1 AUTHOR

Your Name Here

=head1 LICENSE

This is free software; you can redistribute it and/or modify it under
the same terms as Perl itself.

=cut
