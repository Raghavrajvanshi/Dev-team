use strict;
use warnings;
use FindBin;
use JSON::PP;
use Test::More;
require "$FindBin::Bin/lib.pl";
our $REPO;

# How a goal ends: verified | partial | failed | blocked, and what can never be closed as partial.
new_repo();
my ($rc, $out);
dt('init');
my $n = 0;
sub closure { my $f = sprintf "$REPO/.devteam/goals/G-%03d/closure.md", $_[0] // $n; -f $f ? do { local (@ARGV, $/) = $f; <> } : '' }
sub outcome { state()->{outcome}{result} // '' }
sub criteria_file { sprintf "$REPO/.devteam/goals/G-%03d/criteria.json", $n }
# Start a goal and leave it VERIFYING. Each criterion is [id, type, check].
sub goal {
    my @c = @_;
    $n++;
    dt('goal', 'new', "goal $n");
    dt('criteria', 'add', '--id', $_->[0], '--type', $_->[1], '--text', "WHEN $_->[0] THEN it holds", ($_->[2] ? ('--check', $_->[2]) : ())) for @c;
    ($rc, $out) = dt('goal', 'confirm', '--lane', 'standard', '--lifecycle', 'direct');
    die "goal confirm failed: $out" if $rc;
    dt('state', 'transition', 'VERIFYING');
}
sub close_partial { dt('close', '--accept-partial', @_) }
my @OK = ('--reason', 'the mobile view follows in the next goal', '--by', 'user');

# --- verified: the existing path now says so ---
goal(['C1', 'cmd', 'true'], ['C2', 'cmd', 'true']);
($rc, $out) = dt('close');
is($rc, 0, 'verified: every criterion passes') or diag $out;
is(outcome(), 'verified', 'verified: outcome recorded in state');
like(closure(), qr/^outcome: VERIFIED \(2 of 2 criteria pass\)/m, 'verified: the closure report says so');
($rc, $out) = dt('status');
like($out, qr/^outcome: VERIFIED \(2\/2 pass\)/m, 'verified: dt status shows it after the goal closed');
($rc, $out) = dt('ledger');
like($out, qr/goal_closed \(verified\): 1/, 'verified: the ledger records it');

# --- partial: proposal first, then only with the user's reason and acceptance ---
goal(['C1', 'cmd', 'true'], ['C2', 'cmd', 'false'], ['C3', 'manual', '']);
($rc, $out) = dt('close');
isnt($rc, 0, 'partial: a plain close refuses');
like($out, qr/not all verified: C2 C3/, 'partial: the refusal names every open criterion');
($rc, $out) = close_partial();
isnt($rc, 0, 'partial: --accept-partial alone records nothing');
like($out, qr/PARTIAL CLOSE NEEDS THE USER.*- C2: WHEN C2 THEN it holds.*- C3: WHEN C3 THEN it holds.*--by user/s, 'partial: it lists every unmet criterion for the user');
is(state()->{status}, 'VERIFYING', 'partial: still VERIFYING after the proposal');
ok(!closure(), 'partial: no closure report from a proposal');
for my $bad (['--reason', 'because'], ['--by', 'user'], ['--reason', 'because', '--by', 'verifier'], ['--reason', '', '--by', 'user'], ['--reason', '--by', 'user']) {
    ($rc, $out) = close_partial(@$bad);
    like($out, qr/NEEDS THE USER/, "partial: needs a reason and the user ('@$bad')");
}
is(outcome(), '', 'partial: nothing was recorded for this goal yet');
($rc, $out) = close_partial(@OK);
is($rc, 0, 'partial: accepted with a reason by the user') or diag $out;
is(state()->{status}, 'IDLE', 'partial: back to IDLE');
is(outcome(), 'partial', 'partial: outcome recorded');
my $rep = closure();
like($rep, qr/^outcome: PARTIAL \(1 of 3 criteria pass\)/m, 'partial: the report marks it PARTIAL with the counts');
like($rep, qr/^why: accepted as partial by the user: the mobile view follows/m, 'partial: the report keeps the user reason');
like($rep, qr/^- C2 OPEN:/m, 'partial: an open cmd criterion is named');
like($rep, qr/^- C3 OPEN:/m, 'partial: an open manual criterion is named');
like($rep, qr/^- C1 PASS:/m, 'partial: passing criteria are shown too');
is_deeply(state()->{outcome}{open}, [ 'C2', 'C3' ], 'partial: state lists exactly the open criteria');
($rc, $out) = dt('status');
like($out, qr/^outcome: PARTIAL \(1\/3 pass; open: C2 C3\): accepted as partial by the user/m, 'partial: dt status shows it');
($rc, $out) = dt('ledger');
like($out, qr/goal_closed \(partial\): 1/, 'partial: the ledger records it');

# --- partial with failing gates: allowed, but marked in the report ---
dt('state', 'set', 'original_branch=', 'original_sha=');
sh(q{perl -MJSON::PP -e 'open F,"<.devteam/config.json";local $/;$c=decode_json(<F>);$c->{gates}{test}="echo SUITE RED; exit 3";open O,">.devteam/config.json";print O encode_json($c)'});
dt('resync');
goal(['C1', 'cmd', 'true'], ['C2', 'cmd', 'false']);
($rc, $out) = close_partial();
like($out, qr/gates are failing too: .*SUITE RED/s, 'gates: the proposal shows the failing gate');
($rc, $out) = close_partial(@OK);
is($rc, 0, 'gates: partial may be accepted with a red suite') or diag $out;
like(closure(), qr/^gates: FAILING, accepted with the goal: gate 'test' failed/m, 'gates: the report marks them FAILING');
goal(['C1', 'cmd', 'true']);
($rc, $out) = dt('close');
isnt($rc, 0, 'gates: a verified close still refuses on a red suite');
like($out, qr/gate 'test' failed/, 'gates: and says which gate');
dt('state', 'transition', 'STOPPED'); dt('state', 'transition', 'IDLE');
sh(q{perl -MJSON::PP -e 'open F,"<.devteam/config.json";local $/;$c=decode_json(<F>);$c->{gates}{test}="";open O,">.devteam/config.json";print O encode_json($c)'});
dt('resync');

# --- the shape of a partial: something passes and something is open ---
goal(['C1', 'cmd', 'true']);
($rc, $out) = close_partial(@OK);
isnt($rc, 0, 'shape: nothing open is not a partial');
like($out, qr/nothing is partial: use plain dt close/, 'shape: and says to close normally');
is(state()->{status}, 'VERIFYING', 'shape: no state change');
dt('close');
goal(['C1', 'cmd', 'false'], ['C2', 'cmd', 'false']);
($rc, $out) = close_partial(@OK);
isnt($rc, 0, 'shape: no passing criterion is not a partial');
like($out, qr/no criterion passes: that is a failed goal/, 'shape: it is a failed goal');
is(state()->{status}, 'VERIFYING', 'shape: no state change');

# --- failed: stopped without closing ---
dt('state', 'transition', 'STOPPED');
is(outcome(), 'failed', 'failed: stopping a verifying goal records failed');
like(closure(), qr/^outcome: FAILED \(0 of 2 criteria pass\)/m, 'failed: the report says so');
like(closure(), qr/^why: stopped before it was closed \(was VERIFYING\)/m, 'failed: and why');
dt('state', 'transition', 'IDLE');
($rc, $out) = dt('ledger');
like($out, qr/goal_closed \(failed\): \d+/, 'failed: the ledger records it');

# --- blocked: stopped while waiting on the user ---
goal(['C1', 'cmd', 'true']);
dt('state', 'transition', 'ACTIVE');
dt('state', 'transition', 'BLOCKED', 'design needs a decision about the database');
($rc, $out) = dt('status');
unlike($out, qr/^outcome:/m, 'blocked: a blocked goal has no outcome while it is still alive');
dt('state', 'transition', 'STOPPED');
is(outcome(), 'blocked', 'blocked: stopping a blocked goal records blocked');
like(closure(), qr/^why: stopped while blocked: design needs a decision about the database/m, 'blocked: the report keeps the blocking reason');
dt('state', 'transition', 'IDLE');

# --- a goal dropped before it was confirmed has no outcome ---
dt('goal', 'new', 'never confirmed');
$n++;
dt('state', 'transition', 'STOPPED');
is(outcome(), '', 'dropped: a goal never confirmed has no outcome');
ok(!closure(), 'dropped: and no closure report');
dt('state', 'transition', 'IDLE');

# --- stopping is always honoured, even if the goal's files were removed ---
goal(['C1', 'cmd', 'true']);
unlink criteria_file();
($rc, $out) = dt('state', 'transition', 'STOPPED');
is($rc, 0, 'stop: still works when criteria.json is gone') or diag $out;
is(outcome(), 'failed', 'stop: the outcome is still recorded');
dt('state', 'transition', 'IDLE');

# --- the outcome is state dt owns; a new goal starts clean ---
($rc, $out) = dt('state', 'set', 'outcome=verified');
isnt($rc, 0, 'outcome cannot be set by hand');
goal(['C1', 'cmd', 'true']);
is_deeply(state()->{outcome}, {}, 'a new goal starts with no outcome');
dt('close');

# --- what can never close as partial ---
# lock violation, even with the reason and the user's acceptance
sh('echo test > t.txt && git add t.txt && git commit -q -m t');
goal(['C1', 'cmd', 'true'], ['C2', 'cmd', 'false']);
dt('criteria', 'lock', 't.txt');
sh('echo weakened > t.txt');
for my $try (1 .. 2) {
    ($rc, $out) = close_partial(@OK);
    isnt($rc, 0, "lock violation: not a partial close (attempt $try)");
    like($out, qr/locked acceptance tests were changed: t\.txt/, 'lock violation: named');
}
is(state()->{status}, 'VERIFYING', 'lock violation: nothing recorded');
ok(!closure(), 'lock violation: no closure report');
sh('git checkout -q t.txt');
dt('state', 'transition', 'STOPPED'); dt('state', 'transition', 'IDLE');

# a hand-edited criteria.json (flipping a result), on the first and on a second attempt
goal(['C1', 'cmd', 'true'], ['C2', 'manual', '']);
sh(qq{perl -pi -e 's/"passes" : false/"passes" : true/' $REPO/.devteam/goals/G-} . sprintf('%03d', $n) . '/criteria.json');
for my $try (1 .. 2) {
    ($rc, $out) = close_partial(@OK);
    isnt($rc, 0, "tamper: not a partial close (attempt $try)");
    like($out, qr/protected files changed outside dt/, 'tamper: named');
    ($rc, $out) = dt('close');
    isnt($rc, 0, "tamper: not a verified close either (attempt $try)");
}
($rc, $out) = dt('verify');
isnt($rc, 0, 'tamper: dt verify will not re-seal an edit');
is(state()->{status}, 'VERIFYING', 'tamper: nothing recorded');
dt('resync');    # the user reviewed the edit and accepts it
dt('state', 'transition', 'STOPPED'); dt('state', 'transition', 'IDLE');

# a hand-edited state.json
goal(['C1', 'cmd', 'true'], ['C2', 'cmd', 'false']);
sh(q{perl -pi -e 's/"spawns" : 0/"spawns" : 5/' .devteam/state.json});
($rc, $out) = close_partial(@OK);
isnt($rc, 0, 'tamper: an edited state.json cannot close as partial');
like($out, qr/state\.json/, 'tamper: names state.json');
dt('resync');
dt('state', 'transition', 'STOPPED'); dt('state', 'transition', 'IDLE');

# your branch moved under the goal
goal(['C1', 'cmd', 'true'], ['C2', 'cmd', 'false']);
dt('state', 'set', 'original_branch=main', 'original_sha=0000000000000000000000000000000000000000');
($rc, $out) = close_partial(@OK);
isnt($rc, 0, 'branch: a moved branch cannot close as partial');
like($out, qr/your branch 'main' moved/, 'branch: named');

done_testing();
