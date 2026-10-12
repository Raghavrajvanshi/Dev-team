use strict;
use warnings;
use FindBin;
use JSON::PP;
use Test::More;
require "$FindBin::Bin/lib.pl";
our ($PLUGIN, $REPO);

sub slurp { open my $h, '<', $_[0] or die "$_[0]: $!"; local $/; <$h> }
sub crit { my $c = decode_json(slurp("$REPO/.devteam/goals/$_[0]/criteria.json")); +{ map { $_->{id} => $_ } @{ $c->{criteria} } } }

# --- the data: every lifecycle the selector can recommend exists, and is a short, well-formed profile ---
my %sel;
for (split /\n/, slurp("$PLUGIN/lifecycles/_select.tsv")) {
    next if /^#/ || !/\S/;
    $sel{ (split /\t/)[0] } = 1;
}
my @files = grep { !m{/_} } glob("$PLUGIN/lifecycles/*.md");
my %have = map { m{([^/]+)\.md$}; $1 => 1 } @files;
is_deeply([ sort grep { !$have{$_} } keys %sel ], [], 'no selector row names a lifecycle without a file');
is(scalar(keys %have), 8, 'all eight lifecycles are installed');
for my $f (@files) {
    (my $id = $f) =~ s{.*/|\.md$}{}g;
    my $t = slurp($f);
    cmp_ok(scalar(() = $t =~ /\n/g), '<=', 40, "$id: at most 40 lines");
    like($t, qr/\A---\nid: \Q$id\E\nshape: \S.*\ncadence: \S/, "$id: front matter carries its id, shape and cadence");
    like($t, qr/^## Phases/m, "$id: has phases");
    like($t, qr/^## Roles early/m, "$id: says which roles are pulled forward");
    like($t, qr/^## Extra done-checks/m, "$id: has an extra done-checks section");
    unlike($t, qr/\b(?:week|sprint of|days?)\b.*\bcadence\b|^cadence:.*\b(?:weeks?|days?|months?)\b/mi, "$id: cadence is counted in tasks and budget, never calendar");
    my ($sec) = $t =~ /^## Extra done-checks[^\n]*\n(.*?)(?=^## |\z)/ms;
    my @bad = grep { /^\s*-/ && !/^\s*-\s*(?:cmd: \S.* :: \S|judgement: \S|manual: \S)/ } split /\n/, $sec // '';
    is(scalar @bad, 0, "$id: every extra done-check line is a well-formed cmd, judgement or manual check") or diag join "\n", @bad;
}

# --- the selector never recommends a lifecycle that is missing ---
new_repo();
dt('init');
my @missing;
for my $req (qw(stable evolving unclear)) {
    for my $risk (qw(regulated high normal)) {
        for my $size (qw(tiny standard large)) {
            for my $ops (qw(yes no)) {
                my ($rc, $o) = dt('lifecycle', 'suggest', '--requirements', $req, '--risk', $risk, '--size', $size, '--ops', $ops, '--delivery', 'project');
                push @missing, "$req/$risk/$size/$ops: $o" if $o =~ /not installed/;
            }
        }
    }
}
is_deeply(\@missing, [], 'across 54 signal combinations nothing recommended is missing');

# --- done-checks become criteria at confirm ---
my ($rc, $out);
dt('goal', 'new', 'pipeline');
dt('criteria', 'add', '--id', 'C1', '--text', 'WHEN x THEN y', '--check', 'true');
($rc, $out) = dt('goal', 'confirm', '--lane', 'standard', '--lifecycle', 'devops');
is($rc, 0, 'confirm under devops') or diag $out;
like($out, qr/the devops lifecycle added done-checks: L1, L2, L3/, 'and says which done-checks it added');
my $c = crit('G-001');
is_deeply([ map { $c->{$_}{type} } qw(C1 L1 L2 L3) ], [qw(cmd cmd judgement manual)], 'a cmd, a judgement and a manual check join the contract');
like($c->{L1}{check}, qr{^'/[^']*/plugins/devteam/bin/dt' gate run --full --require$}, '{dt} is filled in with this plugin\'s own dt, as an absolute path');
is($c->{L2}{lifecycle}, 'devops', 'each is marked with the lifecycle that added it');
($rc, $out) = dt('criteria', 'show');
like($out, qr/^L3\s+manual\s+open\s+WHEN the owner has run the deploy facts against staging/m, 'dt criteria show lists them');

# the gate check refuses a vacuous pass
($rc, $out) = dt('verify');
is($rc, 1, 'the green-pipeline check fails while no gate is configured');
like($out, qr/FAIL L1.*\n.*no gate is configured/s, 'and says why');
dt('gate', 'set', 'test=true');
($rc, $out) = dt('gate', 'run', '--full', '--require');
is($rc, 0, 'with a gate configured it passes');
($rc, $out) = dt('gate', 'run', '--full');
is($rc, 0, 'dt gate run without --require is unchanged');

# --- changing lifecycle swaps the open checks and keeps what passed ---
dt('criteria', 'confirm', 'L3', '--by', 'user', '--note', 'staging ok');
($rc, $out) = dt('lifecycle', 'set', 'spiral');
is($rc, 0, 'lifecycle set');
like($out, qr/done-checks added: L1, L2/, 'the new profile\'s checks are added, skipping the id that passed');
like($out, qr/done-checks removed.*L1, L2/, 'the old profile\'s open checks are removed');
$c = crit('G-001');
ok($c->{L3}{passes} && $c->{L3}{lifecycle} eq 'devops', 'a check that already passed is kept');
like($c->{L1}{check}, qr{^test -s \.devteam/goals/G-001/reports/risks\.md$}, 'the spiral risk register check uses a path relative to the project');
($rc, $out) = dt('lifecycle', 'set', 'spiral');
unlike($out, qr/done-checks added/, 'setting the same lifecycle again adds nothing');

# --- the tiny lane has no agents, so a judgement check becomes the user's ---
new_repo();
dt('init');
dt('goal', 'new', 'tiny one');
dt('criteria', 'add', '--id', 'C1', '--text', 'WHEN x THEN y', '--check', 'true');
dt('goal', 'confirm', '--lane', 'tiny', '--lifecycle', 'v-model');
$c = crit('G-001');
is_deeply([ map { $c->{$_}{type} } qw(L1 L2) ], [qw(cmd manual)], 'tiny lane: the judgement check is manual');
($rc, $out) = dt('verify');
like($out, qr/FAIL L1/, 'the test-plan check fails until the plan exists');
sh('mkdir -p .devteam/goals/G-001/reports && echo "acceptance: C1" > .devteam/goals/G-001/reports/test-plan.md');
($rc, $out) = dt('verify');
unlike($out, qr/FAIL L1/, 'and passes once QA has written it');

# --- profiles without structured lines add nothing; a project's own profile works ---
new_repo();
dt('init');
dt('goal', 'new', 'plain');
dt('criteria', 'add', '--id', 'C1', '--text', 'WHEN x THEN y', '--check', 'true');
dt('goal', 'confirm', '--lane', 'standard', '--lifecycle', 'waterfall');
is(scalar(grep { /^L/ } keys %{ crit('G-001') }), 0, 'waterfall states a prose check and adds no criterion');
dt('state', 'transition', 'PAUSED');
dt('state', 'transition', 'STOPPED');
dt('state', 'transition', 'IDLE');
sh('mkdir -p .devteam/lifecycles && printf -- "---\nid: mine\nshape: s\ncadence: none\n---\n## Phases\n1. Do.\n## Roles early\nnone\n## Extra done-checks\n- cmd: WHEN done THEN the flag file exists :: test -f {goaldir}/ok.flag\nnot a check line\n- manual: WHEN the owner looks THEN they agree\n" > .devteam/lifecycles/mine.md');
dt('goal', 'new', 'custom');
dt('criteria', 'add', '--id', 'C1', '--text', 'WHEN x THEN y', '--check', 'true');
($rc, $out) = dt('goal', 'confirm', '--lane', 'standard', '--lifecycle', 'mine');
is($rc, 0, 'a project profile can be chosen') or diag $out;
$c = crit('G-002');
is_deeply([ map { $c->{$_}{type} } qw(L1 L2) ], [qw(cmd manual)], 'its structured lines become criteria and prose lines are ignored');
like($c->{L1}{check}, qr{test -f \.devteam/goals/G-002/ok\.flag$}, '{goaldir} points at this goal');

# --- the closure report keeps the owner's words ---
new_repo();
dt('init');
dt('goal', 'new', 'proto');
dt('criteria', 'add', '--id', 'C1', '--text', 'WHEN x THEN y', '--check', 'true');
dt('goal', 'confirm', '--lane', 'standard', '--lifecycle', 'prototype');
dt('criteria', 'confirm', 'L1', '--by', 'verifier', '--note', 'todo.py opens with PROTOTYPE: disposable');
dt('criteria', 'confirm', 'L2', '--by', 'user', '--note', 'rebuild it properly');
dt('state', 'transition', 'VERIFYING');
dt('verify');
($rc, $out) = dt('close');
is($rc, 0, 'the goal closes') or diag $out;
my $closure = slurp("$REPO/.devteam/goals/G-001/closure.md");
like($closure, qr/^- L2 PASS: .* \(confirmed by user: rebuild it properly\)$/m, 'the closure report prints who confirmed a check and what they said');
like($closure, qr/^- L1 PASS: .* \(confirmed by verifier: todo\.py opens with PROTOTYPE: disposable\)$/m, 'for the verifier too');
unlike($closure, qr/^- C1 PASS: .*confirmed by/m, 'a script-checked criterion has no confirmer');

# --- the PM flow uses it ---
my $o = slurp("$PLUGIN/skills/orchestrate/SKILL.md");
like($o, qr/Spawn the roles the profile names under \*Roles early\* first/, 'orchestrate spawns the profile\'s early roles');
like($o, qr/extra done-checks are already criteria \(ids L1, L2/, 'and treats the done-checks as criteria');
like($o, qr/--note "<their words>"`\. A criterion that asks for a decision records the decision itself.*a blanket "yes to everything" is not an answer/, 'a manual criterion that asks for a decision records the decision, not a blanket yes (found live)');
like(slurp("$PLUGIN/skills/goal/SKILL.md"), qr/dt lifecycle checks <name>/, 'intake shows what a lifecycle adds before the user chooses');
like(slurp("$PLUGIN/skills/lifecycle/SKILL.md"), qr/also swaps the profile's done-checks/, 'changing lifecycle says the checks change too');

done_testing;
