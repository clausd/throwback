package MyApi;
use strict;
use warnings;
use base 'CrudApp';
use File::Basename qw(dirname);
use File::Spec;

# Path to this file — used to locate email templates
my $BASE_DIR = dirname(File::Spec->rel2abs(__FILE__));

sub configure {
    my $app = shift;

    # Load configuration (works in both CGI and DevServer mode)
    require CrudApp::Config;
    my $config = CrudApp::Config->load('crudapp.conf');

    # Database: only set up if DevServer hasn't already done it
    unless ($app->dbh) {
        require CrudApp::DB;
        my $adapter = CrudApp::DB->new($config->{database});
        $app->set_db_adapter($adapter);
    }

    # SMTP email (optional — comment out [smtp] in crudapp.conf to disable)
    if ($config->{smtp} && $config->{smtp}{host}) {
        $app->set_smtp($config->{smtp});
    }

    # Base URL for links in emails (used in verification emails)
    $app->{_app_url}  = $config->{server}{app_url}  || '';
    $app->{_app_name} = $config->{server}{app_name} || 'Todo App';
}

# Require email verification before allowing login
sub require_email_verified { return 1 }

# Allow anonymous access for registration
# (register and verify_email are plain methods — no table access check needed)
sub anon_access {
    return {};
}

# ============================================================
# Public endpoints (no auth required)
# ============================================================

# POST /register
# Body: { "username": "...", "password": "...", "email": "..." }
sub register {
    my $app = shift;
    my $input = $app->json_input;

    return $app->render_error("POST with JSON body required", 400)
        unless $input;
    return $app->render_error("username, password and email are required", 400)
        unless $input->{username} && $input->{password} && $input->{email};

    # Basic email format check
    return $app->render_error("Invalid email address", 400)
        unless $input->{email} =~ /\A[^@\s]+\@[^@\s]+\.[^@\s]+\z/;

    # Password length sanity check
    return $app->render_error("Password must be at least 8 characters", 400)
        if length($input->{password}) < 8;

    # Check for existing username / email
    my $taken = $app->query_value(
        "SELECT 1 FROM _auth WHERE username = ?", $input->{username}
    );
    return $app->render_error("Username already taken", 409) if $taken;

    my $email_taken = $app->query_value(
        "SELECT 1 FROM _auth WHERE email = ?", $input->{email}
    );
    return $app->render_error("Email already registered", 409) if $email_taken;

    # Create user (email_verified defaults to 0)
    my $user_id = $app->create_user(
        $input->{username},
        $input->{password},
        {
            tables => {
                todos => {
                    access  => ['create', 'read', 'update', 'delete'],
                    filters => { user_id => '$user.id' },
                }
            }
        },
        $input->{email}
    );

    # Generate one-time verification token
    my $token = $app->create_email_verification($user_id);

    # Build verification URL
    my $base_url = $app->{_app_url}
        || ($ENV{HTTP_ORIGIN} || '')
        || 'http://' . ($ENV{HTTP_HOST} || 'localhost');
    my $verify_url = "$base_url/?verify=$token";

    # Send verification email (silently skip if SMTP not configured)
    if ($app->email) {
        my $template = "$BASE_DIR/email_templates/verify_email.txt";
        eval {
            $app->email->send_template($input->{email}, $template, {
                username   => $input->{username},
                app_name   => $app->{_app_name},
                verify_url => $verify_url,
            });
        };
        warn "Verification email failed: $@" if $@;
    }

    $app->render_json({
        ok      => 1,
        message => 'Account created. Please check your email to verify your address.',
    }, 201);
}

# GET /verify_email/<token>
sub verify_email {
    my $app = shift;
    my $token = $app->path_id;

    return $app->render_error("Verification token required", 400) unless $token;

    my $user_id = $app->consume_email_verification($token);
    return $app->render_error("Invalid or expired verification link", 400)
        unless $user_id;

    $app->render_json({ ok => 1, message => 'Email verified. You can now log in.' });
}

# ============================================================
# Authenticated endpoints
# ============================================================

# GET/POST/DELETE /todos
sub todos {
    my $app = shift;
    $app->crud('todos');
}

1;

__END__

=head1 NAME

MyApi - Example CrudApp API with email verification

=head1 ENDPOINTS

=over 4

=item POST /register

Create a new account. Body: C<{"username":"...","password":"...","email":"..."}>

Returns 201 on success. Sends a verification email.

=item GET /verify_email/:token

Verify the one-time token from the email link. Returns 200 on success.

=item POST /login

Authenticate. Body: C<{"username":"...","password":"..."}>
Login is blocked until the email is verified. Exponential backoff
applies to failed attempts (1s → 2s → 4s → ... → 24h max).

=item POST /logout

Invalidate the current token.

=item GET /todos

List todos for the current user.

=item GET /todos/:id

Get a single todo.

=item POST /todos

Create (no C<id>) or update (with C<id>) a todo.

=item DELETE /todos/:id

Delete a todo.

=back

=head1 CONFIGURATION

See C<crudapp.conf>. SMTP settings go in the C<[smtp]> section.
Set C<app_url> in C<[server]> so verification links point to the right host.

=cut
