# CrudApp

A minimal Perl JSON API framework for shared hosting. Token auth, row-level security, automatic CRUD.

## Install

```bash
make install
```

## Quick Start

```bash
throwback create myapp
cd myapp
throwback initdb
throwback run
# Open http://localhost:3000/ — login: demo / demo123
```

## CLI Commands

| Command | Description |
|---------|-------------|
| `throwback create <dir>` | Scaffold a new project |
| `throwback initdb` | Initialize SQLite dev database + demo user |
| `throwback run` | Start local development server |
| `throwback deploy` | Print deployment guidance |

## Example API Module

```perl
package MyApi;
use base 'CrudApp';

sub configure {
    my $app = shift;
    $app->set_db('mydb', 'user', 'pass');
}

sub todos { shift->crud('todos') }
sub posts { shift->crud('posts') }

1;
```

## JavaScript Client

```javascript
const api = new CrudClient('.');
await api.login('user', 'pass');

const todos = await api.table('todos').list();
await api.table('todos').create({ title: 'New todo' });
await api.table('todos').update(1, { done: 1 });
await api.table('todos').delete(1);
```

## Documentation

See **[llms.txt](llms.txt)** for complete documentation.

## Dependencies

| Production | Local Dev |
|------------|-----------|
| Perl 5.10+ | Perl 5.10+ |
| CGI, DBI, JSON | CGI, DBI, JSON |
| DBD::mysql | DBD::SQLite |
| Digest::SHA | HTTP::Daemon |

## License

MIT
