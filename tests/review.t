use strict;
use warnings;
use FindBin;
use Test::More;
require "$FindBin::Bin/lib.pl";
our ($PLUGIN, $REPO);

sub slurp { open my $h, '<', $_[0] or die "$_[0]: $!"; local $/; <$h> }
my ($rc, $out);

# --- the gate is decided by a script: risky changes trigger it, normal ones do not ---
new_repo();
dt('init');
sh('printf "const total = items.length;\n" > calc.js');
($rc, $out) = dt('risk');
like($out, qr/^review: single pass \(one reviewer\)$/m, 'a normal change gets the single reviewer pass');
unlike($out, qr/gate/, 'and no gate');

sh('printf "function login(u, p) { return true }\n" > session.js');
($rc, $out) = dt('risk');
like($out, qr/^review: gate \(security, correctness and design lenses in parallel\)$/m, 'a trigger opens the gate');

# the goal's own risk, stated at intake, opens it too
new_repo();
dt('init');
sh('printf "const a = 1;\n" > calc.js');
($rc, $out) = dt('risk', 'diff', '--goal-risk', 'high');
like($out, qr/^  goal-risk: high \(stated at intake\)$/m, 'goal risk high is a trigger');
like($out, qr/^review: gate/m, 'and opens the gate');
($rc, $out) = dt('risk', 'diff', '--goal-risk', 'normal');
like($out, qr/^review: single pass/m, 'goal risk normal does not');
($rc, $out) = dt('risk', 'diff', '--goal-risk', 'severe');
isnt($rc, 0, 'an unknown goal risk is an error');
($rc, $out) = dt('risk', '--goal-risk', 'high');
is($rc, 0, 'the options work without the word diff (the form the skill gives the PM; found in the dry run)');
like($out, qr/^review: gate/m, 'and mean the same thing');
($rc, $out) = dt('risk', '--base', 'HEAD', '--goal-risk', 'normal');
like($out, qr/^review: single pass/m, 'also with a base');

# --- a large diff is a trigger in itself (the register's "diff well above the budget") ---
new_repo();
dt('init');
sh(q{perl -e 'print "x$_ = $_;\n" for 1 .. 450' > big.txt});
($rc, $out) = dt('risk');
like($out, qr/^  large-diff: 450 lines added \(the trigger is above 400\)$/m, 'a change adding 450 lines trips the size trigger');
like($out, qr/^review: gate/m, 'and opens the gate');
sh(q{perl -e 'print "x$_ = $_;\n" for 1 .. 399' > big.txt});
($rc, $out) = dt('risk');
unlike($out, qr/large-diff/, 'a change under the line does not');
sh(q{mkdir -p .devteam && printf 'large-diff\tsize\t100\n' > .devteam/risk.tsv});
($rc, $out) = dt('risk');
like($out, qr/large-diff: 399 lines added \(the trigger is above 100\)/, 'a project can lower the line in its own .devteam/risk.tsv');
sh(q{printf 'ticket-ref\tline\tJIRA-\\d+\n' > .devteam/risk.tsv && printf "// JIRA-12\n" > note.js});
($rc, $out) = dt('risk');
like($out, qr/ticket-ref: note\.js:1/, 'and add a trigger of its own');

# --- the closure report prices the review next to the findings ---
new_repo();
dt('init');
dt('engage', 's1');
dt('goal', 'new', 'priced');
dt('criteria', 'add', '--id', 'C1', '--text', 'WHEN x THEN y', '--check', 'true');
dt('goal', 'confirm', '--lane', 'standard', '--lifecycle', 'agile-kanban');
open my $lg, '>>', "$REPO/.devteam/log.jsonl" or die;
for my $a (['reviewer', 100, 20], ['reviewer', 50, 10], ['security-engineer', 30, 6], ['architect', 999, 999]) {
    print $lg qq({"event":"subagent_stop","agent_type":"devteam:$a->[0]","tokens":{"claude-sonnet-5-5":{"input":$a->[1],"output":$a->[2],"cache_read":5000,"cache_write":700}},"ts":"x"}\n);
}
close $lg;
dt('state', 'transition', 'VERIFYING');
($rc, $out) = dt('close');
like(slurp("$REPO/.devteam/goals/G-001/closure.md"), qr/^review: reviewer x2, security-engineer x1 \(in=180 out=36 cache_read=15000 cache_write=2100\)$/m, 'two reviewer passes and one security pass, with their tokens and no other role');

# --- the reviewer's lenses and the re-check ---
my $r = slurp("$PLUGIN/agents/reviewer.md");
like($r, qr/^- \*\*correctness\*\*/m, 'the reviewer has a correctness lens');
like($r, qr/^- \*\*design\*\*/m, 'and a design lens');
like($r, qr/With none named, do both in one pass/, 'with no lens named it keeps doing both, as before');
like($r, qr/HIGH \| MEDIUM \| NIT \| PRE/, 'findings carry a severity the merge can rank');
like($r, qr/PRE.*not introduced by this diff.*never block/s, 'a finding the diff did not introduce is separate and never blocks');
like($r, qr/at most 5 NITs/, 'nits are capped');
like($r, qr/Re-check/, 'a re-check verdicts earlier findings and reads only the fix diff');
unlike($r, qr/^tools:.*(?:Write|Edit)/m, 'every lens stays read-only');
like(slurp("$PLUGIN/agents/security-engineer.md"), qr/Re-check/, 'the Security Engineer has the same re-check');

# --- the PM flow ---
my $o = slurp("$PLUGIN/skills/orchestrate/SKILL.md");
like($o, qr/`dt risk --goal-risk <the goal's risk>`/, 'orchestrate asks the script which review applies');
like($o, qr/`review: gate`.*`review: single pass`/s, 'and follows its answer');
like($o, qr/`lens: correctness`.*`lens: design`/s, 'the gate spawns the two reviewer lenses');
like($o, qr/in one message spawn `security-engineer`.*each with `run_in_background: false`.*all three replies come back together/s, 'in parallel, and the replies come back together');
like($o, qr/drop a finding another lens already reports at the same file and lines/, 'merging drops duplicates');
like($o, qr/scoped re-checks: only the lenses that had blocking findings/, 'later rounds re-check only what was found');
like($o, qr/At most 3 rounds, then an exception stop/, 'and every round is bounded');

done_testing;
