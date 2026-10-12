use strict;
use warnings;
use FindBin;
use Test::More;
require "$FindBin::Bin/lib.pl";
our ($PLUGIN, $REPO);

sub slurp { open my $h, '<', $_[0] or die "$_[0]: $!"; local $/; <$h> }

# A change that trips a security trigger cannot close unless a Security Engineer reviewed it or the user accepts it.
# Found live: in the tiny lane the PM skipped the `dt risk` step, so the user was never asked.
sub goal {
    my ($lane, $code) = @_;
    new_repo();
    dt('init');
    dt('engage', 's1');
    dt('goal', 'new', 'risky');
    dt('criteria', 'add', '--id', 'C1', '--text', 'WHEN x THEN y', '--check', 'true');
    dt('goal', 'confirm', '--lane', $lane, '--lifecycle', $lane eq 'tiny' ? 'direct' : 'agile-kanban');
    sh(qq{printf '%s\\n' '$code' > run.js});
    dt('state', 'transition', 'VERIFYING');
}
my ($rc, $out);

goal('tiny', 'eval(userInput);');
($rc, $out) = dt('close');
is($rc, 1, 'a trigger with no security review is not closed by the script');
like($out, qr/CLOSE NEEDS THE USER'S DECISION \(nothing recorded\).*dynamic-exec: run\.js:1.*dt goal lane standard.*dt close --accept-risk --by user/s, 'it lists the triggers and both ways forward');
is(state()->{status}, 'VERIFYING', 'and nothing changed');
($rc, $out) = dt('close', '--accept-risk');
is($rc, 1, 'accepting without the user is refused');
($rc, $out) = dt('close', '--accept-risk', '--by', 'user');
is($rc, 0, 'the user\'s acceptance closes it') or diag $out;
my $cl = slurp("$REPO/.devteam/goals/G-001/closure.md");
like($cl, qr/^security: no Security Engineer reviewed this goal and the user accepted its triggers: dynamic-exec: run\.js:1$/m, 'and the closure report says so');

# a review that ran during this goal clears it
goal('standard', 'eval(userInput);');
open my $h, '>>', "$REPO/.devteam/log.jsonl" or die;
print $h qq({"event":"subagent_stop","agent_type":"devteam:security-engineer","ts":"2026-10-12T00:00:00Z"}\n);
close $h;
($rc, $out) = dt('close');
is($rc, 0, 'a Security Engineer review during the goal lets it close') or diag $out;
unlike(slurp("$REPO/.devteam/goals/G-001/closure.md"), qr/^security:/m, 'with nothing to record');

# a review that belongs to an earlier goal does not
new_repo();
dt('init');
dt('engage', 's1');
open $h, '>>', "$REPO/.devteam/log.jsonl" or die;
print $h qq({"event":"goal_confirm","goal":"G-000","ts":"x"}\n{"event":"subagent_stop","agent_type":"devteam:security-engineer","ts":"x"}\n);
close $h;
dt('goal', 'new', 'second');
dt('criteria', 'add', '--id', 'C1', '--text', 'WHEN x THEN y', '--check', 'true');
dt('goal', 'confirm', '--lane', 'tiny', '--lifecycle', 'direct');
sh(q{printf 'eval(x);\n' > run.js});
dt('state', 'transition', 'VERIFYING');
($rc, $out) = dt('close');
is($rc, 1, 'a review from a previous goal does not count');

# nothing to flag, nothing asked
goal('tiny', 'const a = 1;');
($rc, $out) = dt('close');
is($rc, 0, 'a change with no trigger closes as before') or diag $out;

done_testing;
