use diagnostics; # this gives you more debugging information
use warnings;    # this warns you of bad practices
use strict;      # this prevents silly errors

use TAP::Harness;

my %args = (
    verbosity => 1,
    color => 1,
);

my $harness = TAP::Harness->new (\%args);
$harness->runtests(
    # 'install.t',
    'run.t',
);

