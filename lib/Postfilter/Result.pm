package Postfilter::Result;

use strict;
use warnings;

=head1 NAME

Postfilter::Result - Immutable-in-practice result object for one filter check.

=head1 DESCRIPTION

A result separates the technical verdict from the final administrative action.
For example, audit mode can retain a technical C<reject> while returning success
to the NNTP client.  Rule actions may additionally request C<discard> or C<save>;
the policy resolver remains the only component that decides the final INN reply.

=cut

# Function: pass
# Purpose: Creates a successful check result without selecting the final administrative action.
# Parameters: $class, %arguments
# Operational notes: Operates only on the small result object and has no external side effects.
sub pass {
    my ($class, %arguments) = @_;
    return bless { verdict => 'pass', %arguments }, $class;
}

# Function: reject
# Purpose: Creates a technical rejection result while retaining symbolic and historical codes.
# Parameters: $class, %arguments
# Operational notes: Operates only on the small result object and has no external side effects.
sub reject {
    my ($class, %arguments) = @_;
    return bless { verdict => 'reject', %arguments }, $class;
}

# Function: error
# Purpose: Creates an internal-error result for callers that need to distinguish failure from
#          policy rejection.
# Parameters: $class, %arguments
# Operational notes: Operates only on the small result object and has no external side effects.
sub error {
    my ($class, %arguments) = @_;
    return bless { verdict => 'error', %arguments }, $class;
}

# Function: is_pass
# Purpose: Returns true only when the technical verdict is pass.
# Parameters: $_[0] (the current object or value)
# Operational notes: Operates only on the small result object and has no external side effects.
sub is_pass {
    return $_[0]->{verdict} eq 'pass';
}

# Function: is_reject
# Purpose: Returns true only when the technical verdict is reject.
# Parameters: $_[0] (the current object or value)
# Operational notes: Operates only on the small result object and has no external side effects.
sub is_reject {
    return $_[0]->{verdict} eq 'reject';
}

# Function: code
# Purpose: Returns the symbolic Postfilter-NG reason code.
# Parameters: $_[0] (the current object or value)
# Operational notes: Operates only on the small result object and has no external side effects.
sub code {
    return $_[0]->{code} // 'PF-INTERNAL-000';
}

# Function: legacy
# Purpose: Returns the historical numeric code retained for migration and reporting.
# Parameters: $_[0] (the current object or value)
# Operational notes: Operates only on the small result object and has no external side effects.
sub legacy {
    return defined $_[0]->{legacy} ? $_[0]->{legacy} : 0;
}

# Function: message
# Purpose: Returns the human-readable result explanation.
# Parameters: $_[0] (the current object or value)
# Operational notes: Operates only on the small result object and has no external side effects.
sub message {
    return $_[0]->{message} // '';
}

# Function: requested_action
# Purpose: Returns an optional action requested by a matching rule, such as discard or save.
# Parameters: $_[0] (the current object or value)
# Operational notes: Operates only on the small result object and has no external side effects.
sub requested_action {
    return $_[0]->{requested_action};
}

# Function: as_hash
# Purpose: Returns a shallow hash copy suitable for JSON, tests, or diagnostic output.
# Parameters: $_[0] (the current object or value)
# Operational notes: Operates only on the small result object and has no external side effects.
sub as_hash {
    return { %{ $_[0] } };
}

1;
