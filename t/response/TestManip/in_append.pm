package TestManip::in_append;

# this test demonstrates how to write manip() callback to append new headers
# to existins headers. Here we added header 'Leech'.

use strict;
use warnings FATAL => 'all';

use base qw(Apache::Filter::HTTPHeadersFixup);

use Apache::RequestRec ();
use Apache::RequestIO ();

use APR::Table ();

use Apache::TestTrace;

use Apache::Const -compile => qw(OK M_POST);

my $key = "Leech";
my $val = "Hungry";

sub manip {
    my ($class, $ra_headers) = @_;
    # don't forget the new line!
    my $header = "$key: $val\n";
    debug "appending: [$header]";
    push @$ra_headers, $header;
    debug "returning @{[ 0+@$ra_headers ]} headers";
}

sub response {
    my $r = shift;

    my $data = $r->method_number == Apache::M_POST
        ? ModPerl::Test::read_post($r)
        : '';

    $r->content_type('text/plain');
    $r->print($data);

    # copy the input header to output headers
    $r->headers_out->set($key => $r->headers_in->get($key));

    return Apache::OK;
}

1;
__END__
<NoAutoConfig>
<VirtualHost TestManip::in_append>
  # must be preloaded so the FilterConnectionHandler attributes will
  # be set by the time the filter is inserted into the filter chain
  PerlModule TestManip::in_append
  PerlInputFilterHandler TestManip::in_append
  <Location /TestManip__in_append>
     SetHandler modperl
     PerlResponseHandler TestManip::in_append::response
  </Location>
</VirtualHost>
</NoAutoConfig>
