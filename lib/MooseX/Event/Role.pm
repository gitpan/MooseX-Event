# ABSTRACT: A Node style event Role for Moose
package MooseX::Event::Role;
{
  $MooseX::Event::Role::VERSION = '0.3.0_2';
}
use MooseX::Event ();
use Any::Moose 'Role';
use Scalar::Util qw( refaddr reftype blessed );
use Event::Wrappable ();


sub metaevent {
    my $self = shift;
    my( $event ) = @_;
    my $accessor = $self->can("event:$event");
    return defined $accessor ? $self->$accessor() : undef;
}


sub get_all_events {
    my $self = shift;
    return map {substr($_,6)} grep {/^event:/} map {$_->name} $self->meta->get_all_attributes;
}


sub event_listeners {
    my $self = shift;
    my( $event ) = @_;
    my $emeta = $self->metaevent($event);
    unless ( $emeta ) {
        require Carp;
        Carp::confess("Event $event does not exist");
    }
    my @listeners = values %{$emeta->listeners};
    return wantarray? @listeners : scalar @listeners;
}

# Having the first argument flatten the argument list isn't actually allowed
# in Rakudo (and possibly P6 too)


sub on {
    my $self = shift;
    my $listener = pop;

    # If it's not an Event::Wrappable object, make it one.
    if ( ! blessed $listener or ! $listener->isa("Event::Wrappable") ) {
        $listener = &Event::Wrappable::event( $listener );
    }

    for my $event (@_) {
        my $emeta = $self->metaevent($event);
        unless ( $emeta ) {
            require Carp;
            Carp::confess("Event $event does not exist");
        }
        $emeta->listen( $listener );
    }
    return $listener;
}

sub once {
    my $self = shift;
    my $listener = pop;

    # If it's not an Event::Wrappable object, make it one.
    if ( ! blessed $listener or ! $listener->isa("Event::Wrappable") ) {
        $listener = &Event::Wrappable::event( $listener );
    }

    for my $event (@_) {
        my $emeta = $self->metaevent($event);
        unless ( $emeta ) {
            require Carp;
            Carp::confess("Event $event does not exist");
        }
        $emeta->listen_once( $listener );
    }
    return $listener;
}

sub emit {
    my $self = shift;
    my( $event, @args ) = @_;
    # The event object attributes are lazy, so if one doesn't exist yet
    # don't trigger the creation of it just to fire events into the void
    if ( reftype $self eq 'HASH' ) {
        return unless exists $self->{"event:$event"};
    }
    my $emeta = $self->metaevent($event);
    unless ( $emeta ) {
        require Carp;
        Carp::confess("Event $event does not exist");
    }
    $emeta->emit_self( @args );
}



sub remove_all_listeners {
    my $self = shift;
    foreach ($self->get_all_events) {
        $self->metaevent($_)->stop_all_listeners;
    }
}


sub remove_listener {
    my $self = shift;
    my( $event, $listener ) = @_;
    my $emeta = $self->metaevent($event);
    unless ( $emeta ) {
        require Carp;
        Carp::confess("Event $event does not exist");
    }
    $emeta->stop_listener($listener);
}

1;


__END__
=pod

=encoding utf-8

=head1 NAME

MooseX::Event::Role - A Node style event Role for Moose

=head1 VERSION

version 0.3.0_2

=head1 DESCRIPTION

This is the role that L<MooseX::Event> extends your class with.  All classes
using MooseX::Event will have these methods, attributes and events.

=head1 ATTRIBUTES

=head2 my Str $.current_event is ro

This is the name of the current event being triggered, or undef if no event
is being triggered.

=head1 METHODS

=head2 method metaevent( Str $event ) returns Bool

Returns true if $event is a valid event name for this class.

=head2 method get_all_events() returns List

Returns a list of all registered event names in this class and any superclasses.

=head2 method event_listeners( Str $event ) returns Array|Int

In array context, returns a list of all of the event listeners for a
particular event.  In scalar context, returns the number of listeners
registered.

=head2 method on( Array[Str] *@events, CodeRef $listener ) returns CodeRef

Registers $listener as a listener on $event.  When $event is emitted all
registered listeners are executed.

If you are using L<Coro> then listeners are called in their own thread,
which makes them fully Coro safe.  There is no need to use "unblock_sub"
with MooseX::Event.

Returns the listener coderef.

=head2 method once( Str $event, CodeRef $listener ) returns CodeRef

Registers $listener as a listener on $event. Event listeners registered via
once will emit only once.

Returns the listener coderef.

=head2 method emit( Str $event, *@args )

Normally called within the class using the MooseX::Event role.  This calls all
of the registered listeners on $event with @args.

If you're using L<Coro> then each listener is executed in its own thread.
Emit will return immediately, the event listeners won't execute until you
cede or block in some manner.  Normally this isn't something you have to
think about.

This means that MooseX::Event's listeners are Coro safe and can safely cede
or do other Coro thread related tasks.  That is to say, you don't ever need
to use unblock_sub.

=head2 method remove_all_listeners( Str $event )

Removes all listeners for $event

=head2 method remove_listener( Str $event, CodeRef $listener )

Removes $listener from $event

=head1 SEE ALSO



=over 4

=item *

L<MooseX::Event|MooseX::Event>

=item *

L<MooseX::Event::Role::ClassMethods|MooseX::Event::Role::ClassMethods>

=back

=head1 SOURCE

The development version is on github at L<http://https://github.com/iarna/MooseX-Event>
and may be cloned from L<git://https://github.com/iarna/MooseX-Event.git>

=head1 AUTHOR

Rebecca Turner <becca@referencethis.com>

=head1 COPYRIGHT AND LICENSE

This software is copyright (c) 2012 by Rebecca Turner.

This is free software; you can redistribute it and/or modify it under
the same terms as the Perl 5 programming language system itself.

=head1 DISCLAIMER OF WARRANTY

BECAUSE THIS SOFTWARE IS LICENSED FREE OF CHARGE, THERE IS NO WARRANTY
FOR THE SOFTWARE, TO THE EXTENT PERMITTED BY APPLICABLE LAW. EXCEPT
WHEN OTHERWISE STATED IN WRITING THE COPYRIGHT HOLDERS AND/OR OTHER
PARTIES PROVIDE THE SOFTWARE "AS IS" WITHOUT WARRANTY OF ANY KIND,
EITHER EXPRESSED OR IMPLIED, INCLUDING, BUT NOT LIMITED TO, THE
IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR
PURPOSE. THE ENTIRE RISK AS TO THE QUALITY AND PERFORMANCE OF THE
SOFTWARE IS WITH YOU. SHOULD THE SOFTWARE PROVE DEFECTIVE, YOU ASSUME
THE COST OF ALL NECESSARY SERVICING, REPAIR, OR CORRECTION.

IN NO EVENT UNLESS REQUIRED BY APPLICABLE LAW OR AGREED TO IN WRITING
WILL ANY COPYRIGHT HOLDER, OR ANY OTHER PARTY WHO MAY MODIFY AND/OR
REDISTRIBUTE THE SOFTWARE AS PERMITTED BY THE ABOVE LICENCE, BE LIABLE
TO YOU FOR DAMAGES, INCLUDING ANY GENERAL, SPECIAL, INCIDENTAL, OR
CONSEQUENTIAL DAMAGES ARISING OUT OF THE USE OR INABILITY TO USE THE
SOFTWARE (INCLUDING BUT NOT LIMITED TO LOSS OF DATA OR DATA BEING
RENDERED INACCURATE OR LOSSES SUSTAINED BY YOU OR THIRD PARTIES OR A
FAILURE OF THE SOFTWARE TO OPERATE WITH ANY OTHER SOFTWARE), EVEN IF
SUCH HOLDER OR OTHER PARTY HAS BEEN ADVISED OF THE POSSIBILITY OF SUCH
DAMAGES.

=cut

