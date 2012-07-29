# ABSTRACT: A meta object for events
package MooseX::Event::Meta;
{
  $MooseX::Event::Meta::VERSION = '0.3.0_2';
}
use Any::Moose;
use MooseX::Event;

has 'object' => (is=>'ro',weak_ref=>1);
has 'listeners' => (is=>'ro',default=>sub{ {} });


MooseX::Event::has_event('first_listener');


MooseX::Event::has_event('add_listener');


MooseX::Event::has_event('remove_listener');


MooseX::Event::has_event('no_listeners');


sub listen {
    my $self = shift;
    my( $listener ) = @_;

    # If it's not an Event::Wrappable object, make it one.
    if ( ! blessed $listener or ! $listener->isa("Event::Wrappable") ) {
        $listener = &Event::Wrappable::event( $listener );
    }

    if ( ! %{$self->{'listeners'}} and exists $self->{'event:first_listener'} ) {
        $self->emit('first_listener', $listener);
    }
    if ( exists $self->{'event:add_listener'} ) {
        $self->emit('add_listener', $listener);
    }
    $self->{'listeners'}->{$listener->object_id} = $listener;
    return $listener;
}


sub listen_once {
    my $self = shift;
    my($listener) = @_;
    my $wrapped;
    $wrapped = Event::Wrappable::event { &$listener; $self->stop_listener($wrapped) };
    $self->listen( $wrapped );
    return $wrapped;
}


sub stop_listener {
    my $self = shift;
    my( $listener ) = @_;

    unless (blessed $listener) {
        use Carp;
        croak("Listener wasn't blessed");
    }

    delete $self->{'listeners'}{$listener->object_id};
    if ( exists $self->{'event:remove_listener'} ) {
        $self->emit('remove_listener',$listener);
    }
    if ( ! %{$self->{'listeners'}} and exists $self->{'event:no_listeners'} ) {
        $self->emit('no_listeners');
    }
}


sub stop_all_listeners {
    my $self = shift;
    foreach (sort grep {defined $_} values %{$self->listeners}) {
        $self->stop_listener($_);
    }
}

sub DEMOLISH {
    my $self = shift;
    $self->stop_all_listeners();
    # If Coro is loaded, immediately cede to ensure that any events triggered
    # by removing listeners are executed before the object is destroyed
    if ( defined *Coro::cede{CODE} ) {
        Coro::cede();
    }
}

BEGIN {
    # What we're doing here is building up a separate set of methods for
    # with coroutines and without.

    # The first time you call one of these methods, we check to see if
    # coroutines are loaded and from that point forward only use the
    # version appropriate to that.

    my %alternatives;

    {
        my @events;
        $alternatives{'stock'} = {
            "emit" => sub {
                my $self = shift;
                my @args = ($self->object, @_);
                foreach ( sort keys %{ $self->{'listeners'} } ) {
                    my $todo = $self->{'listeners'}{$_};
                    $todo->(@args);
                }
                return;
            },
        };
    }

    {
        my %events;
        $alternatives{'coro'} = {
            "emit" => sub {
                my $self = shift;
                my @args = ( $self->object, @_ );
                foreach ( sort keys %{ $self->{'listeners'} } ) {
                    my $todo = $self->{'listeners'}{$_};
                    &Coro::async_pool( $todo, @args );
                }
                return;
            },
        };
    }


    my $use_coro_or_not = sub {
        no warnings 'redefine';
        my $sub = shift;
        my $which;

        if ( defined $Coro::current ) {
            $which = $alternatives{'coro'};
        }
        else {
            $which = $alternatives{'stock'};
        }
        my $class = ref $_[0];
        no strict 'refs';
        # This is a role, so we want to modify both our role and the class
        # we're used in directly.
        *{$class.'::emit_self'}            = $which->{'emit'};
        return $which->{$sub};
    };

    sub emit_self {
        goto $use_coro_or_not->( "emit", @_ );
    };


}



1;


__END__
=pod

=encoding utf-8

=head1 NAME

MooseX::Event::Meta - A meta object for events

=head1 VERSION

version 0.3.0_2

=head1 SYNOPSIS

    {
        package MyClass;
        use MooseX::Event;

        has_event 'ping';
    }

    my $obj = MyClass->new;
    $obj->metaevent('ping')->on( add_listener => sub { say "Listener added to ping" } );
    $obj->metaevent('ping')->on( remove_listener => sub { say "Listener removed from ping" } );
    $obj->metaevent('ping')->on( first_listener => sub { say "First listener on ping" } );
    $obj->metaevent('ping')->on( no_listeners => sub { say "No listeners left on ping" } );

    my $ping1 = $obj->on( ping => sub { say "Ping 1!"; } );
    # first_listener event fires and prints "First listener on ping"
    # add_listener event fires and prints "Listener added to ping"

    my $ping2 = $obj->on( ping => sub { say "Ping 2!"; } );
    # add_listener event fires and prints "Listener added to ping"

    $obj->emit('ping');
    # both ping event listeners fire and print "Ping 1!" and "Ping 2!"

    $obj->remove_listener(ping=>$ping1);
    # remove_listener fires and prints "Listener removed from ping"

    $obj->emit('ping');
    # second ping event listener fires and prints "Ping 2!"

    $obj->remove_listener(ping=>$ping2);
    # remove_listener fires and prints "Listener removed from ping"
    # no_listeners fires and prints "No listeners left on ping"

    $obj->once( ping => sub { say "Ping 3!"; } );
    # first_listener event fires and prints "First listener on ping"
    # add_listener event fires and prints "Listener added to ping"

    $obj->emit('ping');
    # new ping event listener fires and prints "Ping 3!"
    # Since this is a "once" event, it is then removed...
    # remove_listener fires and prints "Listener removed from ping"
    # no_listeners fires and prints "No listeners left on ping"

    say "Done";

=head1 DESCRIPTION

This object is used to track information about each event on an object.  It
can be used to trigger on meta-data events, like adding and removing of
listeners.  It's also used internally to implement MooseX::Event::Role's
methods.

=head1 EVENTS

=head2 first_listener( Str $event, CodeRef $listener )

Called when a listener is added and no listeners were yet registered for this event.

=head2 add_listener( Str $event, CodeRef $listener )

Called before a listener is added.  $listener is the listener being installed.

=head2 remove_listener( Str $event, CodeRef $listener )

Called after a listener is removed.  $listener is the listener being removed.

=head2 no_listeners( Str $event )

Called when a listener is removed and there are no more listeners registered
for this event.  This will fire prior to new_listener.

=head1 METHODS

=head2 method listen( CodeRef $listener ) returns CodeRef

Registers $listener as a listener on this event.  When the emit method is
called all registered listeners are executed.  registered listeners are
executed.

If you are using L<Coro> then listeners are called in their own thread,
which makes them fully Coro safe.  There is no need to use "unblock_sub"
with MooseX::Event.

Returns the listener coderef.

=head2 method listen_once( CodeRef $listener ) returns CodeRef

Registers $listener as a listener on this event. Event listeners registered
via listen_once will emit only once.

Returns the listener coderef.

=head2 method stop_listener( CodeRef $listener )

Stop emitting events to $listener

=head2 method stop_all_listeners( CodeRef $listener )

Stop emitting any events

=head2 DEMOLISH
We clean up after ourselves by clearing out all listeners prior to shutting down.

=head2 method emit_self( *@args )

This calls all of the registered listeners on this event with @args.

If you're using L<Coro> then each listener is executed in its own thread.
Emit will return immediately, the event listeners won't execute until you
cede or block in some manner.  Normally this isn't something you have to
think about.

This means that MooseX::Event's listeners are Coro safe and can safely cede
or do other Coro thread related tasks.  That is to say, you don't ever need
to use unblock_sub.

=for test_synopsis use v5.10.0;

=head1 SEE ALSO



=over 4

=item *

L<MooseX::Event|MooseX::Event>

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

