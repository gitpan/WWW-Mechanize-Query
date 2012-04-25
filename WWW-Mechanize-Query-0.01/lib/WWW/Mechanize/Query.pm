use strict;
use warnings;

package WWW::Mechanize::Query;

=head1 NAME

WWW::Mechanize::Query - CSS3 selectors support for WWW::Mechanize.

=head1 VERSION

Version 0.01

=cut

our $VERSION = '0.01';

=head1 SYNOPSIS

	use WWW::Mechanize::Query;

	my $mech = WWW::Mechanize::Query->new( ignore_cache => 0 );
	$mech->get( 'http://www.amazon.com/' );
	$mech->input( 'input[type="text"][name="field-keywords"]', 'Perl' );
	$mech->submit();

	print $mech->find('h2.resultCount')->span->text; #prints "Showing 1 - 16 of 7,104 Results"

=head1 DESCRIPTION

This module combines L<WWW::Mechanize> with L<Mojo::DOM> making it possible to fill forms and scrape web with help of CSS3 selectors. 

For a full list of supported CSS selectors please see L<Mojo::DOM::CSS>.

=cut

use parent qw(WWW::Mechanize);
use Cache::FileCache;
use Storable qw( freeze thaw );
use Data::Dumper;
use Mojo::DOM;

=head1 CONSTRUCTOR

=head2 new

Creates a new L<WWW::Mechanize>'s C<new> object with any passed arguments. 

WWW::Mechanize::Query also adds simple request caching (unless I<ignore_cache> is set to true). Also sets I<Firefox> as the default user-agent (if not explicitly specified). 

	my $mech = WWW::Mechanize::Query->new( ignore_cache => 0, agent => 'LWP' );

=cut

sub new {
    my $class     = shift;
    my %mech_args = @_;

    if ( !$mech_args{agent} ) {
        $mech_args{agent} = 'Mozilla/5.0 (Windows NT 6.1; WOW64; rv:11.0) Gecko/20100101 Firefox/11.0';
    }

    my $self = bless \%mech_args, $class;

    $self->{'_internal'}->{'cache'} = Cache::FileCache->new( {default_expires_in => "1d", namespace => 'www-mechanize-query',} );
    $self->{'_internal'}->{'mojo'} = Mojo::DOM->new();

    return $self;
}

sub _make_request {
    my $self     = shift;
    my $request  = shift;
    my $req      = $request->as_string;
    my $cache    = ( !$self->{ignore_cache} && ( $request->method eq 'GET' ) ) ? $self->{'_internal'}->{'cache'} : undef;
    my $response = '';

    if ( $cache ) {
        my $cached = $cache->get( $req );

        if ( $cached ) {
            $response = thaw $cached;
        }
    }

    if ( !$response ) {
        $response = $self->SUPER::_make_request( $request, @_ );

        if ( $response->is_success && $cache ) {
            $cache->set( $req, freeze( $response ) );
        }
    }

    return $response;
} ## end sub _make_request

=head1 METHODS

Methods provided by L<WWW::Mechanize> can be accessed directly. 

Methods provided by L<Mojo::DOM> are accessible by calling I<dom()> method.

=head2 dom()

Parses the current content and returns a L<Mojo::DOM> object.

	my $dom = $mech->dom;
	print $dom->to_xml();

=cut

sub dom {
    my $self    = shift;
    my $content = $self->content;

    if ( !$self->{'_internal'}->{'_last_content'} || ( $content ne $self->{'_internal'}->{'_last_content'} ) || !$self->{'_internal'}->{'_last_dom'} ) {
        $self->{'_internal'}->{'_last_content'} = $content;
        $self->{'_internal'}->{'_last_dom'}     = $self->{'_internal'}->{'mojo'}->parse( $content );
    }

    return $self->{'_internal'}->{'_last_dom'};
}

=head2 find()

Parses the current content and returns a L<Mojo::DOM> object using CSS3 selectors.

	my $mech = WWW::Mechanize::Query->new();
	$mech->get( 'http://www.amazon.com/' );
	print $mech->find( 'div > h2' )->text;

=cut

sub find {
    my $self = shift;
    my $expr = shift;

    return $self->dom->at( $expr );
}

=head2 input()

Gets or sets Form fields using CSS3 selectors.

	my $mech = WWW::Mechanize::Query->new();
	$mech->get( 'http://www.imdb.com/' );
	$mech->input( 'input[name="q"]', 'lost' );    #fill name
	$mech->input( 'select[name="s"]', 'ep' );     #select "TV" from drop-down list
	$mech->submit();

	print $mech->content;
	print $mech->input( 'input[name="q"]' );      #prints "lost";

	#TODO: Right now it fills out the first matching field but should be restricted to selected form.

=cut

sub input {
    my $self   = shift;
    my $ele    = shift;
    my $value  = shift;
    my $getter = !defined( $value );

    if ( ref( $ele ) ne 'Mojo::DOM' ) {
        $ele = $self->find( $ele );
    }

    die "No '$ele' exists" unless $ele;
    die "Not supported" unless ( $ele->type =~ /input|select|textarea/i );

    my $dom = $self->dom;

    if ( ( $ele->type =~ /input/i ) && ( $ele->attrs( 'type' ) =~ /text|email|password|hidden|number/i ) ) {
        if ( $getter ) {
            return $ele->attrs( 'value' );
        }

        $ele->attrs( {'value' => $value} );
    } elsif ( ( $ele->type =~ /input/i ) && ( $ele->attrs( 'type' ) =~ /checkbox|radio/i ) ) {
        my $collection = $dom->find( 'input[type="' . $ele->attrs( 'type' ) . '"][name="' . $ele->attrs( 'name' ) . '"]' ) || return;

        if ( $getter ) {
            my @result = ();
            $collection->each( sub { my $e = shift; push( @result, $e->attrs( 'value' ) ) if exists( $e->attrs()->{'checked'} ); } );
            return wantarray ? @result : $result[0];
        }

        $collection->each(
            sub {
                my $e = shift;
                if ( lc $e->attrs( 'value' ) eq lc $value ) {
                    $e->attrs( 'checked', 'checked' );
                } else {
                    delete( $e->attrs()->{'checked'} );
                }
            }
        );
    } elsif ( $ele->type =~ /select/i ) {
        my $options = $ele->find( 'option' . ( $getter ? ':checked' : '' ) ) || return;

        if ( $getter ) {
            return $options->map( sub { my $e = shift; return $e->attrs( 'value' ) || $e->text; } );
        }

        $options->each(
            sub {
                my $e = shift;
                my $v = $e->attrs( 'value' ) || $e->text;

                if ( lc $v eq lc $value ) {
                    $e->attrs( 'selected', 'selected' );
                } else {
                    delete( $e->attrs()->{'selected'} );
                }
            }
        );
    } elsif ( $ele->type =~ /textarea/i ) {
        if ( $getter ) {
            return $ele->text();
        }

        $ele->prepend_content( $value );
    } else {
        die 'Unknown or Unsupported type';
    }

    $self->update_html( $dom->to_xml );
} ## end sub input

=head1 SEE ALSO

L<WWW::Mechanize>.

L<Mojo::DOM>

L<WWW::Mechanize::Cached>.

=head1 AUTHORS

=over 4

=item *

San Kumar (robotreply at gmail)

=back

=head1 COPYRIGHT AND LICENSE

This software is copyright (c) 2012 by San Kumar.

This is free software; you can redistribute it and/or modify it under
the same terms as the Perl 5 programming language system itself.

=cut


1;
