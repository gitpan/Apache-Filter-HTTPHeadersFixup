use strict;
use warnings FATAL => 'all';

use Apache::Test;
use Apache::TestUtil;
use Apache::TestRequest;

plan tests => 6;

my $module = 'TestManip::in_modify';
my $location = "/" . Apache::TestRequest::module2path($module);

Apache::TestRequest::scheme('http'); #force http for t/TEST -ssl
Apache::TestRequest::module($module);

my $config = Apache::Test::config();
my $hostport = Apache::TestRequest::hostport($config);
t_debug("connecting to $hostport");

my $key = "Sign-Here";
my $val = "DigSig";

{
    my $content = "Top Input Security";
    my $res = POST $location,
        content  => $content,
            $key  => "";

    ok t_cmp($content, $res->content, "the content came through");

    ok t_cmp($val, $res->header($key)||'', "modified header / POST ");
}

{
    my $res = GET $location, $key  => "";

    ok t_cmp("", $res->content, "there should be no content / GET");

    ok t_cmp($val, $res->header($key)||'', "modified header / GET ");
}

{
    my $res = HEAD $location, $key  => "";

    ok t_cmp("", $res->content, "there should be no response body / HEAD ");

    ok t_cmp($val, $res->header($key)||'', "modified header / HEAD ");
}
