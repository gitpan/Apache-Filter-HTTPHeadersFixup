package Apache::Filter::HTTPHeadersFixup;

$Apache::Filter::HTTPHeadersFixup::VERSION = '0.01';

use strict;
use warnings FATAL => 'all';

use mod_perl 1.9911; # 1.99_10 has a bug in filters insertion code

use base qw(Apache::Filter);

use APR::Brigade ();
use APR::Bucket ();

use Apache::TestTrace;

use Apache::Const -compile => qw(OK DECLINED);
use APR::Const    -compile => ':common';

# this is the function that needs to be overriden
sub manip {
    my ($class, $ra_headers) = @_;
    warn "You should write a subclass of " . __PACKAGE__  .
        " since by default HTTP headers are left intact\n";
}

# perl < 5.8 can't handle more than one attribute in the subroutine
# definition so add the "method" attribute separately
use attributes ();
attributes::->import(__PACKAGE__ => \&handler, "method");

sub handler : FilterConnectionHandler {

    debug join '', "-" x 20 ,
        (@_ == 6 ? " input" : " output") . " filter called ", "-" x 20;

    # $mode, $block, $readbytes are passed only for input filters
    # so there are 3 more arguments
    return @_ == 6 ? handle_input(@_) : handle_output(@_);

}

sub context {
    my ($filter) = shift;

    my $ctx;
    unless ($ctx = $filter->ctx) {
        debug "filter context init";
        $ctx = {
            headers             => [],
            done_with_headers   => 0,
            seen_body_separator => 0,
        };
        # since we are going to manipulate the reference stored in
        # ctx, it's enough to store it only once, we will get the same
        # reference in the following invocations of that filter
        $filter->ctx($ctx);
    }
    return $ctx;
}

sub handle_output {
    my($class, $filter, $bb) = @_;

    my $ctx = context($filter);

    # handling the HTTP request body
    if ($ctx->{done_with_headers}) {
        # XXX: when the bug in httpd filter will be fixed remove the
        # filter:
        #   $filter->remove;
        # at the moment (2.0.48) it doesn't work
        # so meanwhile tell the mod_perl filter core to pass-through
        # the brigade unmodified
        debug "passing the body through unmodified";
        my $rv = $filter->next->pass_brigade($bb);
        return $rv unless $rv == APR::SUCCESS;
        return Apache::OK;
    }

    my $data = '';
    for (my $b = $bb->first; $b; $b = $bb->next($b)) {
        $b->read(my $bdata);
        $bdata = '' unless defined $bdata;
        $data .= $bdata;
    }

    debug "data: $data\n";

    while ($data =~ /(.*\n)/g) {
        my $line = $1;
        debug "READ: [$line]";
        if ($line =~ /^[\r\n]+$/) {
            # let the user function do the manipulation of the headers
            # without the separator, which will be added when the
            # manipulation has been completed
            $ctx->{done_with_headers}++;
            $class->manip($ctx->{headers});
            my $data = join '', @{ $ctx->{headers} }, "\n";
            $ctx->{headers} = [];
            my $c = $filter->c;
            my $out_bb = APR::Brigade->new($c->pool, $c->bucket_alloc);
            $out_bb->insert_tail(APR::Bucket->new($data));
            my $rv = $filter->next->pass_brigade($out_bb);
            return $rv unless $rv == APR::SUCCESS;
            return Apache::OK;
            # XXX: is it possible that some data will be along with
            # headers in the same incoming bb?
        }
        else {
            push @{ $ctx->{headers} }, $line;
        }
    }

    return Apache::OK;
}

sub handle_input {
    my($class, $filter, $bb, $mode, $block, $readbytes) = @_;

    my $ctx = context($filter);

    # handling the HTTP request body
    if ($ctx->{done_with_headers}) {
        # XXX: when the bug in httpd filter will be fixed remove the
        # filter:
        #   $filter->remove;
        # at the moment (2.0.48) it doesn't work
        # so meanwhile tell the mod_perl filter core to pass-through
        # the brigade unmodified
        debug "passing the body through unmodified";
        return Apache::DECLINED;
    }

    # any custom input HTTP header buckets to inject?
    return Apache::OK if inject_header_bucket($bb, $ctx);

    # normal HTTP headers processing
    my $c = $filter->c;
    until ($ctx->{seen_body_separator}) {
        my $ctx_bb = APR::Brigade->new($c->pool, $c->bucket_alloc);
        my $rv = $filter->next->get_brigade($ctx_bb, $mode, $block, $readbytes);
        return $rv unless $rv == APR::SUCCESS;

        while (!$ctx_bb->empty) {
            my $data;
            my $bucket = $ctx_bb->first;

            $bucket->remove;

            if ($bucket->is_eos) {
                debug "EOS!!!";
                $bb->insert_tail($bucket);
                last;
            }

            my $status = $bucket->read($data);
            debug "filter read:\n[$data]";
            return $status unless $status == APR::SUCCESS;

            if ($data =~ /^[\r\n]+$/) {
                # normally the body will start coming in the next call to
                # get_brigade, so if your filter only wants to work with
                # the headers, it can decline all other invocations if that
                # flag is set. However since in this test we need to send 
                # a few extra bucket brigades, we will turn another flag
                # 'done_with_headers' when 'seen_body_separator' is on and
                # all headers were sent out
                debug "END of original HTTP Headers";
                $ctx->{seen_body_separator}++;

                # let the user function do the manipulation of the headers
                # without the separator, which will be added when the
                # manipulation has been completed
                $class->manip($ctx->{headers});

                # but at the same time we must ensure that the
                # the separator header will be sent as a last header
                # so we send one newly added header and push the separator
                # to the end of the queue
                push @{ $ctx->{headers} }, "\n";
                debug "queued header [$data]";
                inject_header_bucket($bb, $ctx);
                last; # there should be no more headers in $ctx_bb
                # notice that if we didn't inject any headers, this will
                # still work ok, as inject_header_bucket will send the
                # separator header which we just pushed to its queue
            } else {
                push @{ $ctx->{headers} }, $data;
            }
        }
    }

    return Apache::OK;
}
# returns 1 if a bucket with a header was inserted to the $bb's tail,
# otherwise returns 0 (i.e. if there are no headers to insert)
sub inject_header_bucket {
    my ($bb, $ctx) = @_;

    return 0 unless @{ $ctx->{headers} };

    # extra debug, wasting cycles
    my $data = shift @{ $ctx->{headers} };
    $bb->insert_tail(APR::Bucket->new($data));
    debug "injected header: [$data]";

    # next filter invocations will bring the request body if any
    if ($ctx->{seen_body_separator} && !@{ $ctx->{headers} }) {
        $ctx->{done_with_headers}   = 1;
    }

    return 1;
}

1;
__END__

=pod

=head1 NAME

Apache::Filter::HTTPHeadersFixup - Manipulate Apache 2 HTTP Headers

=head1 Synopsis

  # MyApache/FixupInputHTTPHeaders.pm
  package MyApache::FixupInputHTTPHeaders;
  
  use strict;
  use warnings FATAL => 'all';
  
  use base qw(Apache::Filter::HTTPHeadersFixup);
  
  sub manip {
      my ($class, $ra_headers) = @_;
  
      # modify a header
      for (@$ra_headers) {
          s/^(Foo).*/$1: Moahaha/;
      }
  
      # push header (don't forget "\n"!)
      push @$ra_headers, "Bar: MidBar\n";
  }
  1;

  # httpd.conf
  <VirtualHost Zoot>
      PerlModule MyApache::FixupInputHTTPHeaders
      PerlInputFilterHandler MyApache::FixupInputHTTPHeaders
  </VirtualHost>

  # similar for output headers

=head1 Description

C<Apache::Filter::HTTPHeadersFixup> is a super class which provides an
easy way to manipulate HTTP headers without invoking any mod_perl HTTP
callbacks. This is accomplished by using input and output connection
filters.

This class cannot be used as is. It has to be subclassed. Read on.

=head1 Usage

A new class inheriting from C<Apache::Filter::HTTPHeadersFixup> needs
to be created. That class needs to include a single function
C<manip()>. This function is invoked with two arguments, the package
it was invoked from and a reference to an array of headers, each
terminated with a new line.

That function can manipulate the values in that hash. It shouldn't
return anything. That means you can't assign to the reference itself
or the headers will be lost.

Now you can modify, add or remove headers.

The function works indentically for input and output HTTP headers.

See the L<Synopsis> section for an example and more examples can be
seen in the test suite.

=head1 Debug

C<Apache::Filter::HTTPHeadersFixup> includes internal tracing calls,
which make it easy to debug the parsing of the headers. For example to
run a test with tracing enabled do:

  % t/TEST -trace=debug -v manip/out_append

Or you can set the C<APACHE_TEST_TRACE_LEVEL> to I<debug> at the
server startup:

  APACHE_TEST_TRACE_LEVEL=debug apachectl start

All the tracing goes into I<error_log>.

=head1 Bugs

=head1 See Also

L<Apache2>, L<mod_perl>, L<Apache::Filter>

=head1 Authors

Stas Bekman <stas@stason.org>

=head1 Copyright

The C<Apache::Filter::HTTPHeadersFixup> module is free software; you
can redistribute it and/or modify it under the same terms as Perl
itself.

=cut

