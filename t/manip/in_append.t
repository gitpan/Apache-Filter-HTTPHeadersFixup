use strict;
use warnings FATAL => 'all';

use Apache::Test;
use Apache::TestUtil;
use Apache::TestRequest;

plan tests => 6;

my $module = 'TestManip::in_append';
my $location = "/" . Apache::TestRequest::module2path($module);

Apache::TestRequest::scheme('http'); #force http for t/TEST -ssl
Apache::TestRequest::module($module);

my $config = Apache::Test::config();
my $hostport = Apache::TestRequest::hostport($config);
t_debug("connecting to $hostport");

my $key = "Leech";
my $val = "Hungry";

{
    my $content = "Wet Grasslands";
    my $res = POST $location, content  => $content;

    ok t_cmp($content, $res->content, "the content came through");

    ok t_cmp($val, $res->header($key)||'', "appended header");
}

{
    my $res = GET $location;

    ok t_cmp("", $res->content, "there should be no content / GET");

    ok t_cmp($val, $res->header($key)||'', "appended header / GET ");
}

{
    my $res = HEAD $location;

    ok t_cmp("", $res->content, "there should be no content / HEAD");

    ok t_cmp($val, $res->header($key)||'', "appended header / HEAD ");
}


