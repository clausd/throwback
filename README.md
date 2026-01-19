# CrudApp

A minimal JSON API framework for Perl CGI with maximum shared hosting compatibility.

## Features

- **Minimal dependencies**: CGI, DBI, JSON, Digest::SHA (all standard)
- **No external modules required**: Works on vanilla Perl 5.10+
- **Token-based authentication**: Secure, stateless auth
- **Per-user access control**: Row-level security filters
- **Automatic CRUD**: Expose database tables with one line of code
- **Static frontend + API pattern**: Fast static file serving, CGI only for API

## Quick Start

### 1. Upload Files

Upload to your server:

```
your-app/
├── CrudApp.pm          # The framework (from this repo)
├── MyApi.pm            # Your API module
├── api.cgi             # CGI entry point
├── .htaccess           # Apache rewrite rules
├── index.html          # Your frontend
└── js/
    └── crud-client.js  # JavaScript client
```

### 2. Create Database

```bash
mysql -u user -p your_database < schema.sql
```

### 3. Configure

Edit `MyApi.pm`:

```perl
sub configure {
    my $app = shift;
    $app->set_db('your_database', 'your_user', 'your_password');
}
```

### 4. Set Permissions

```bash
chmod 755 api.cgi
chmod 755 create_user.pl
```

### 5. Create a User

```bash
perl create_user.pl demo demo123
```

### 6. Test

```bash
# Test API
curl https://yoursite.com/your-app/

# Login
curl -X POST https://yoursite.com/your-app/login \
  -H "Content-Type: application/json" \
  -d '{"username":"demo","password":"demo123"}'
```

## Dependencies

**Required** (all standard or widely available):

| Module | Notes |
|--------|-------|
| CGI | Core module |
| DBI | Standard, usually pre-installed |
| DBD::mysql | MySQL driver |
| JSON | Widely available |
| Digest::SHA | Core since Perl 5.10 |

**Not Required**:

- No Template Toolkit
- No CGI::Session
- No Cache::FileCache
- No DBIx::Abstract
- No custom modules

## API Reference

### Authentication

```
POST /login
Body: {"username": "user", "password": "pass"}
Response: {"token": "abc123...", "expires": 1234567890}

POST /logout
Header: Authorization: Bearer <token>
Response: {"ok": 1}
```

### CRUD Operations

```
GET /todos              # List (with pagination)
GET /todos?limit=10     # Paginated list
GET /todos/123          # Get single record
POST /todos             # Create (body without id)
POST /todos             # Update (body with id)
DELETE /todos/123       # Delete
```

### Response Format

Success:
```json
{"data": [...], "limit": 20, "offset": 0}
```

Error:
```json
{"error": "Error message"}
```

## Creating Your API

### 1. Define Your Module

```perl
# MyApi.pm
package MyApi;
use strict;
use base 'CrudApp';

sub configure {
    my $app = shift;
    $app->set_db('mydb', 'user', 'pass');
}

# Optional: Allow anonymous access
sub anon_access {
    return {
        posts => ['read']  # Anyone can read posts
    };
}

# Expose tables via automatic CRUD
sub posts { shift->crud('posts') }
sub todos { shift->crud('todos') }
sub comments { shift->crud('comments') }

# Custom endpoint with join query
sub posts_with_authors {
    my $app = shift;
    my $posts = $app->query_rows(
        "SELECT p.*, u.username as author
         FROM posts p
         JOIN _auth u ON u.id = p.user_id
         WHERE p.status = ?
         ORDER BY p.created_at DESC",
        'published'
    );
    $app->render_json({ data => $posts });
}

1;
```

### 2. Create Entry Point

```perl
#!/usr/bin/perl
# api.cgi
use strict;
use lib '.';
use MyApi;
MyApi->new->run;
```

### 3. Configure Apache

The `.htaccess` file routes requests:

- Static files (HTML, CSS, JS) → Served directly by Apache
- Everything else → Routed to `api.cgi`

## Access Control

User permissions are stored as JSON in the `_auth.access_rules` column:

```json
{
    "tables": {
        "todos": {
            "access": ["create", "read", "update", "delete"],
            "filters": {
                "user_id": "$user.id"
            }
        }
    }
}
```

### Access Types

- `read` - GET requests
- `create` - POST without id
- `update` - POST with id
- `delete` - DELETE requests
- `*` - All operations

### Filters

Filters restrict which records a user can access:

```json
"filters": { "user_id": "$user.id" }
```

This means users can only see/modify records where `user_id` equals their own ID.

## Database Schema

Required tables:

```sql
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
```

Your application tables (example):

```sql
CREATE TABLE todos (
    id INT AUTO_INCREMENT PRIMARY KEY,
    user_id INT NOT NULL,
    title VARCHAR(255) NOT NULL,
    done TINYINT(1) DEFAULT 0,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (user_id) REFERENCES _auth(id) ON DELETE CASCADE
);
```

## Custom Queries

For joins, aggregations, and complex queries beyond simple CRUD:

### Query Methods

```perl
# Single row (returns hashref or undef)
my $row = $app->query_row($sql, @params);

# Multiple rows (returns arrayref of hashrefs)
my $rows = $app->query_rows($sql, @params);

# Single value (returns scalar)
my $count = $app->query_value($sql, @params);

# Single column (returns arrayref)
my $ids = $app->query_column($sql, @params);

# Execute non-SELECT (INSERT, UPDATE, DELETE)
$app->query_do($sql, @params);
```

### Examples

```perl
# Join: todos with user info
sub todos_detailed {
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

# Aggregation: dashboard stats
sub dashboard {
    my $app = shift;
    my $user = $app->current_user;
    return $app->render_error("Unauthorized", 401) unless $user;

    $app->render_json({
        total => $app->query_value(
            "SELECT COUNT(*) FROM todos WHERE user_id = ?",
            $user->{id}
        ),
        completed => $app->query_value(
            "SELECT COUNT(*) FROM todos WHERE user_id = ? AND done = 1",
            $user->{id}
        )
    });
}

# Search with LIKE
sub search {
    my $app = shift;
    my $q = $app->param('q') or return $app->render_error("Query required", 400);

    my $results = $app->query_rows(
        "SELECT id, title FROM posts WHERE title LIKE ? LIMIT 20",
        "%$q%"
    );
    $app->render_json({ data => $results });
}
```

## JavaScript Client

```javascript
const api = new CrudClient('/api');

// Login
await api.login('username', 'password');

// CRUD operations
const { data: todos } = await api.table('todos').list();
const todo = await api.table('todos').create({ title: 'New todo' });
await api.table('todos').update(todo.id, { done: 1 });
await api.table('todos').delete(todo.id);

// Custom endpoints work too
const response = await api.request('GET', 'dashboard');
const searchResults = await api.request('GET', 'search?q=hello');

// Logout
api.logout();
```

## Troubleshooting

### 500 Internal Server Error

1. Check Apache error log: `tail -f /var/log/apache2/error.log`
2. Verify permissions: `chmod 755 api.cgi`
3. Check Perl syntax: `perl -c api.cgi`

### 404 Not Found

1. Verify `.htaccess` is read (requires `AllowOverride All`)
2. Check `RewriteBase` matches your URL path
3. Ensure `mod_rewrite` is enabled

### Database Connection Failed

1. Verify credentials in `MyApi.pm`
2. Check MySQL user has access from web server
3. Test: `mysql -u user -p database`

### CORS Errors

For same-origin (recommended), no CORS needed. If frontend is on different domain, add to `api.cgi`:

```perl
print "Access-Control-Allow-Origin: *\n";
print "Access-Control-Allow-Headers: Authorization, Content-Type\n";
print "Access-Control-Allow-Methods: GET, POST, DELETE\n";
```

## License

MIT License - use freely in your projects.
