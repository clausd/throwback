package MyApi;
use strict;
use warnings;
use base 'CrudApp';

sub configure {
    my $app = shift;
    # Update these with your database credentials
    $app->set_db('your_database', 'your_user', 'your_password');
}

# Allow anonymous access to certain tables
# Return hash of { table => [allowed_operations] }
sub anon_access {
    return {
        # posts => ['read'],  # Uncomment to allow anonymous read
    };
}

# Expose the 'todos' table
# Users can only see/modify their own todos (based on access_rules filter)
sub todos {
    my $app = shift;
    $app->crud('todos');
}

# Add more tables as needed:
# sub posts { shift->crud('posts') }
# sub categories { shift->crud('categories') }

1;

__END__

=head1 NAME

MyApi - Example CrudApp API for Todo application

=head1 DESCRIPTION

This is an example API module that extends CrudApp to provide
a simple todo list application.

=head1 CONFIGURATION

Edit the configure() method to set your database credentials:

    sub configure {
        my $app = shift;
        $app->set_db('mydb', 'user', 'password');
    }

=head1 ENDPOINTS

=over 4

=item GET /

API status and version info.

=item POST /login

Authenticate with username/password, get token.

=item POST /logout

Invalidate current token.

=item GET /todos

List todos for current user.

=item GET /todos/:id

Get single todo.

=item POST /todos

Create or update todo (include id in body to update).

=item DELETE /todos/:id

Delete todo.

=back

=head1 ACCESS CONTROL

Users can only access their own todos. This is enforced by the
filter in their access_rules:

    {"tables": {"todos": {"access": ["*"], "filters": {"user_id": "$user.id"}}}}

=cut
