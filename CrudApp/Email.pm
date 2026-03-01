package CrudApp::Email;
use strict;
use warnings;
use Net::SMTP;

#############################################################################
# CrudApp::Email - Simple SMTP email sender with template support
#
# Usage:
#   use CrudApp::Email;
#   my $mailer = CrudApp::Email->new({
#       host      => 'smtp.example.com',
#       port      => 587,
#       user      => 'noreply@example.com',
#       pass      => 'secret',
#       from      => 'noreply@example.com',
#       from_name => 'My App',
#       starttls  => 1,   # STARTTLS on port 587
#       # ssl => 1,       # Direct TLS/SSL on port 465
#   });
#
#   $mailer->send('user@example.com', 'Hello', 'Email body here');
#
#   $mailer->send_template('user@example.com', '/path/to/template.txt', {
#       username   => 'Alice',
#       verify_url => 'https://example.com/?verify=abc123',
#   });
#
# Template format:
#   Subject: Your subject line with {{variable}} substitution
#
#   Body text starts after the blank line.
#   Use {{variable_name}} for substitutions.
#############################################################################

sub new {
    my ($class, $config) = @_;
    bless {
        host      => $config->{host}      || 'localhost',
        port      => $config->{port}      || 25,
        user      => $config->{user}      || '',
        pass      => $config->{pass}      || '',
        from      => $config->{from}      || 'noreply@localhost',
        from_name => $config->{from_name} || '',
        ssl       => $config->{ssl}       || 0,
        starttls  => $config->{starttls}  || 0,
    }, $class;
}

sub send {
    my ($self, $to, $subject, $body) = @_;

    my $smtp = Net::SMTP->new(
        $self->{host},
        Port    => $self->{port},
        Timeout => 30,
        SSL     => $self->{ssl} ? 1 : 0,
    ) or die "Cannot connect to SMTP server $self->{host}:$self->{port}";

    if ($self->{starttls}) {
        $smtp->starttls() or die "STARTTLS negotiation failed";
    }

    if ($self->{user}) {
        $smtp->auth($self->{user}, $self->{pass})
            or die "SMTP authentication failed for $self->{user}";
    }

    my $from_addr = $self->{from};
    my $from_header = $self->{from_name}
        ? "$self->{from_name} <$from_addr>"
        : $from_addr;

    $smtp->mail($from_addr)   or die "SMTP MAIL FROM failed";
    $smtp->to($to)            or die "SMTP RCPT TO failed";
    $smtp->data()             or die "SMTP DATA failed";
    $smtp->datasend("MIME-Version: 1.0\n");
    $smtp->datasend("Content-Type: text/plain; charset=UTF-8\n");
    $smtp->datasend("From: $from_header\n");
    $smtp->datasend("To: $to\n");
    $smtp->datasend("Subject: $subject\n");
    $smtp->datasend("\n");
    $smtp->datasend($body);
    $smtp->dataend()          or die "SMTP . failed";
    $smtp->quit;

    return 1;
}

# Load a template file, substitute {{variables}}, then send.
# Template format: first line must be "Subject: ...", then a blank line, then body.
sub send_template {
    my ($self, $to, $template_file, $vars) = @_;

    open my $fh, '<:encoding(UTF-8)', $template_file
        or die "Cannot read email template '$template_file': $!";
    my $content = do { local $/; <$fh> };
    close $fh;

    # Substitute {{variable}} placeholders
    $content =~ s/\{\{(\w+)\}\}/defined $vars->{$1} ? $vars->{$1} : ''/ge;

    # Parse Subject from first line
    my ($subject, $body);
    if ($content =~ /\ASubject:\s*([^\n]*)\n\n?(.*)/s) {
        $subject = $1;
        $body    = $2;
    } else {
        $subject = '(no subject)';
        $body    = $content;
    }

    return $self->send($to, $subject, $body);
}

1;

__END__

=head1 NAME

CrudApp::Email - Simple SMTP email sender with template support

=head1 SYNOPSIS

    use CrudApp::Email;

    my $mailer = CrudApp::Email->new({
        host      => 'smtp.example.com',
        port      => 587,
        user      => 'noreply@example.com',
        pass      => 'secret',
        from      => 'noreply@example.com',
        from_name => 'My App',
        starttls  => 1,
    });

    # Send a plain email
    $mailer->send('user@example.com', 'Hello!', 'Welcome to the app.');

    # Send from a template file
    $mailer->send_template(
        'user@example.com',
        '/path/to/verify_email.txt',
        {
            username   => 'Alice',
            app_name   => 'My App',
            verify_url => 'https://example.com/?verify=TOKEN',
        }
    );

=head1 CONFIGURATION

=over 4

=item host

SMTP server hostname.

=item port

SMTP server port. Defaults to 25. Use 587 for STARTTLS, 465 for SSL.

=item user / pass

SMTP authentication credentials. Leave empty for unauthenticated relay.

=item from

Sender email address (used in envelope and From header).

=item from_name

Optional display name for the From header.

=item ssl

Set to 1 to use direct SSL/TLS (SMTPS). Typically used with port 465.
Requires IO::Socket::SSL.

=item starttls

Set to 1 to upgrade the connection with STARTTLS after connecting.
Typically used with port 587. Requires IO::Socket::SSL.

=back

=head1 TEMPLATE FORMAT

Templates are plain text files. The first line must be the subject,
followed by a blank line, then the message body:

    Subject: Welcome to {{app_name}}

    Hello {{username}},

    Please verify your email: {{verify_url}}

Use C<{{variable_name}}> for substitutions passed in the vars hashref.

=head1 DEPENDENCIES

=over 4

=item Net::SMTP (core)

=item IO::Socket::SSL (required for ssl or starttls options)

=item Authen::SASL (required for SMTP authentication)

=back

=cut
