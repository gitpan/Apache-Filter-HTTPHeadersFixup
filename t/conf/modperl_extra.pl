
use lib qw(lib);

use constant IOBUFSIZE => 8192;

use Apache::Const -compile => qw(MODE_READBYTES);
use APR::Const    -compile => qw(SUCCESS BLOCK_READ);

# to enable debug start with: (or simply run with -trace=debug)
# t/TEST -trace=debug -start
sub ModPerl::Test::read_post {
    my $r = shift;
    my $debug = shift || 0;

    my @data = ();
    my $seen_eos = 0;
    my $filters = $r->input_filters();
    my $ba = $r->connection->bucket_alloc;
    my $bb = APR::Brigade->new($r->pool, $ba);

    my $count = 0;
    do {
        my $rv = $filters->get_brigade($bb,
            Apache::MODE_READBYTES, APR::BLOCK_READ, IOBUFSIZE);
        if ($rv != APR::SUCCESS) {
            return $rv;
        }

        $count++;

        warn "read_post: bb $count\n" if $debug;

        while (!$bb->empty) {
            my $buf;
            my $b = $bb->first;

            $b->remove;

            if ($b->is_eos) {
                warn "read_post: EOS bucket:\n" if $debug;
                $seen_eos++;
                last;
            }

            my $status = $b->read($buf);
            if ($status != APR::SUCCESS) {
                return $status;
            }
            warn "read_post: DATA bucket: [$buf]\n" if $debug;
            push @data, $buf;
        }

        $bb->destroy;

    } while (!$seen_eos);

    return join '', @data;
}

1;
