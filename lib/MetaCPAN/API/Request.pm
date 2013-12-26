package MetaCPAN::API::Request;

use Moo;

use Carp;

use HTTP::Tiny;
use JSON;
use Try::Tiny;
use URI::Escape 'uri_escape';
use List::Util 'first';

has base_url => (
    is      => 'ro',
    default => sub { 'http://api.metacpan.org/v0' },
);

has ua => (
    is      => 'ro',
    lazy    => 1,
    builder => '_build_ua',
);

has ua_args => (
    is      => 'ro',
    default => sub {
        return [ agent => 'MetaCPAN::API/'.($MetaCPAN::API::VERSION||'xx') ];
    },
    lazy => 1,
);


sub _build_ua {
    my $self = shift;
    return HTTP::Tiny->new( @{ $self->ua_args } );
}

sub fetch {
    my $self    = shift;
    my $url     = shift or croak "fetch must be called with a URL param";

    my $extra   = $self->_build_extra_params(@_);
    my $req_url = sprintf "%s/%s?%s", $self->base_url, $url, $extra;

    my $result  = $self->ua->get($req_url);
    return $self->_decode_result( $result, $req_url );
}

sub post {
    my $self  = shift;
    my $url   = shift or croak 'First argument of URL must be provided';
    my $query = shift;

    ref $query eq 'HASH'
        or croak 'Second argument of query hashref must be provided';

    my $query_json = to_json( $query, { canonical => 1 } );

    my $result = $self->ua->request(
        'POST',
        sprintf("%s/%s", $self->base_url, $url),
        {
            headers => { 'Content-Type' => 'application/json' },
            content => $query_json,
        }
    );

    return $self->_decode_result( $result, $url, $query_json );
}

sub _decode_result {
    my $self     = shift;
    my $result   = shift;
    my $url      = shift or croak 'Second argument of a URL must be provided';

    ref $result eq 'HASH'
        or croak 'First argument must be hashref';

    my $success = $result->{'success'};
    defined $success or croak 'Missing success in return value';
    $success or croak "Failed to fetch '$url': " . $result->{'reason'};

    my $content = $result->{'content'} or
        croak 'Missing content in return value';

    my $decoded_result;
    try   { $decoded_result = decode_json $content }
    catch { croak "Couldn't decode '$content': $_" };

    return $decoded_result;
}

sub _build_extra_params {
    my $self = shift;

    @_ % 2 == 0
        or croak 'Incorrect number of params, must be key/value';
    my %extra = @_;

    # if it's deep, JSON encoding needs to be involved
    %extra = ( source => to_json( \%extra, { canonical => 1 } ) )
        if first { ref } values %extra;

    return join '&' =>
        map  { "$_=" . uri_escape( $extra{$_} ) }
        sort keys %extra;
}


1;

__END__

=head1 ATTRIBUTES

=head2 base_url

    my $mcpan = MetaCPAN::API->new(
        base_url => 'http://localhost:9999',
    );

This attribute is used for REST requests. You should set it to where the
MetaCPAN is accessible. By default it's already set correctly, but if you're
running a local instance of MetaCPAN, or use a local mirror, or tunnel it
through a local port, or any of those stuff, you would want to change this.

Default: I<http://api.metacpan.org/v0>.

This attribute is read-only (immutable), meaning that once it's set on
initialize (via C<new()>), you cannot change it. If you need to, create a
new instance of MetaCPAN::API. Why is it immutable? Because it's better.

=head2 ua

This attribute is used to contain the user agent used for running the REST
request to the server. It is specifically set to L<HTTP::Tiny>, so if you
want to set it manually, make sure it's of HTTP::Tiny.

HTTP::Tiny is used as part of the philosophy of keeping it tiny.

This attribute is read-only (immutable), meaning that once it's set on
initialize (via C<new()>), you cannot change it. If you need to, create a
new instance of MetaCPAN::API. Why is it immutable? Because it's better.

=head2 ua_args

    my $mcpan = MetaCPAN::API->new(
        ua_args => [ agent => 'MyAgent' ],
    );

The arguments that will be given to the L<HTTP::Tiny> user agent.

This attribute is read-only (immutable), meaning that once it's set on
initialize (via C<new()>), you cannot change it. If you need to, create a
new instance of MetaCPAN::API. Why is it immutable? Because it's better.

The default is a user agent string: B<MetaCPAN::API/$version>.

=head1 METHODS

=head2 fetch

    my $result = $mcpan->fetch('/release/distribution/Moose');

    # with parameters
    my $more = $mcpan->fetch(
        '/release/distribution/Moose',
        param => 'value',
    );

This is a helper method for API implementations. It fetches a path from
MetaCPAN, decodes the JSON from the content variable and returns it.

You don't really need to use it, but you can in case you want to write your
own extension implementation to MetaCPAN::API.

It accepts an additional hash as C<GET> parameters.

=head2 post

    # /release&content={"query":{"match_all":{}},"filter":{"prefix":{"archive":"Cache-Cache-1.06"}}}
    my $result = $mcpan->post(
        'release',
        {
            query  => { match_all => {} },
            filter => { prefix => { archive => 'Cache-Cache-1.06' } },
        },
    );

The POST equivalent of the C<fetch()> method. It gets the path and JSON request.
