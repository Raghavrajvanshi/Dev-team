use strict;
use warnings;
use FindBin;
use JSON::PP;
use Test::More;
require "$FindBin::Bin/lib.pl";
our $REPO;

new_repo();
dt('init');
my ($rc, $out) = dt('status');
like($out, qr/setup: incomplete \(models not chosen; no project profile; no standards\)/, 'a fresh project reports everything setup still needs');
dt('engage', 's1');
dt('goal', 'new', 'tiny fix');
dt('criteria', 'add', '--id', 'C1', '--text', 'WHEN x THEN y', '--check', 'true');
($rc, $out) = dt('goal', 'confirm', '--lane', 'tiny', '--lifecycle', 'direct');
is($rc, 0, 'tiny goal confirmed');
is(state()->{spawn_cap}, 0, 'tiny lane has a spawn cap of zero');

my $spawn = { session_id => 's1', tool_name => 'Agent', tool_input => { subagent_type => 'devteam:fullstack-engineer' } };
($rc, $out) = hook('guard', $spawn);
like($out, qr/"permissionDecision":"deny".*spawn cap reached \(0\/0 for the tiny lane\)/, 'tiny lane: no agent may start');

dt('goal', 'lane', 'standard');
($rc, $out) = hook('guard', $spawn);
is($out, '', 'upgrading to standard allows agents');
is(state()->{spawns}, 1, 'and the spawn is counted');

# the full tiny path with no agents: verify, close, back to IDLE
dt('goal', 'lane', 'tiny');
dt('state', 'transition', 'VERIFYING');
($rc, $out) = dt('close');
is($rc, 0, 'a tiny goal closes through dt with no agents') or diag $out;
is(state()->{status}, 'IDLE', 'and the team is idle again');
done_testing;
