use strict;
use warnings FATAL => 'all';

require 5.006;

use Apache2;
use ModPerl::MM ();

# enable 'make test|clean'
use Apache::TestMM qw(test clean);

# prerequisites
my %require = (
    # the keepalive constants and the keepalives() method added in 1.9913
    "mod_perl"      => "1.9915",
    "Apache::Test"  => "1.10", # ipv6 fixes
);

my @scripts = qw(t/TEST);

# accept the configs from command line
Apache::TestMM::filter_args();
Apache::TestMM::generate_script('t/TEST');

ModPerl::MM::WriteMakefile(
    NAME         => 'Apache::Filter::HTTPHeadersFixup',
    VERSION_FROM => 'lib/Apache/Filter/HTTPHeadersFixup.pm',
    PREREQ_PM    => \%require,
    dist         => {
        PREOP => 'pod2text lib/Apache/Filter/HTTPHeadersFixup.pm > $(DISTVNAME)/README',
    },
    clean        => {
        FILES => "@{ clean_files() }",
    }
);

sub clean_files {
    return \@scripts;
}



__END__
