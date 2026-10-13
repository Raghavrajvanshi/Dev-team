use strict;
use warnings;
use FindBin;
use JSON::PP;
use Test::More;
require "$FindBin::Bin/lib.pl";
our ($PLUGIN, $REPO);

sub slurp { open my $h, '<', $_[0] or die "$_[0]: $!"; local $/; <$h> }
sub ledger { grep { length } split /\n/, (-f "$REPO/.devteam/log.jsonl" ? slurp("$REPO/.devteam/log.jsonl") : '') }
sub decision { my $j = eval { decode_json($_[0]) } or return ''; $j->{hookSpecificOutput}{permissionDecision} // '' }
sub words { join ' ', ('word') x $_[0] }

sub fresh {
    new_repo();
    dt('init');
    dt('engage', 's1');
    dt('goal', 'new', 'discuss');
    dt('criteria', 'add', '--id', 'C1', '--text', 'WHEN x THEN y', '--check', 'true');
    dt('goal', 'confirm', '--lane', 'standard', '--lifecycle', 'agile-kanban');
}
my @new = ('--question', 'Keep the retry loop in the client or move it to the worker?',
    '--evidence', 'Reviewer: retries belong in the worker. Engineer: the client owns the timeout.',
    '--options', 'A=Keep it in the client|B=Move it to the worker', '--participants', 'architect,reviewer');
sub open_one { my %x = @_; dt('discuss', 'new', '--trigger', $x{trigger} // 'dispute', @new) }
my ($rc, $out, $c, $o2);

# --- a discussion needs a trigger, an active goal outside the tiny lane, and well-formed input ---
fresh();
($rc, $out) = dt('discuss', 'new', @new);
isnt($rc, 0, 'no trigger, no discussion');
like($out, qr/--trigger dispute\|options\|user/, 'and it names the three triggers');
($rc, $out) = dt('discuss', 'new', '--trigger', 'curiosity', @new);
isnt($rc, 0, 'an unknown trigger is refused');
for my $case (
    ['no question',        [ '--trigger', 'dispute', '--evidence', 'e', '--options', 'A=x|B=y', '--participants', 'architect,reviewer' ], qr/--question/],
    ['no evidence',        [ '--trigger', 'dispute', '--question', 'q?', '--options', 'A=x|B=y', '--participants', 'architect,reviewer' ], qr/--evidence/],
    ['one option',         [ '--trigger', 'dispute', '--question', 'q?', '--evidence', 'e', '--options', 'A=x', '--participants', 'architect,reviewer' ], qr/2 to 4 options/],
    ['a bad option id',    [ '--trigger', 'dispute', '--question', 'q?', '--evidence', 'e', '--options', 'A=x|Z=y', '--participants', 'architect,reviewer' ], qr/ids A to D/],
    ['one participant',    [ '--trigger', 'dispute', '--question', 'q?', '--evidence', 'e', '--options', 'A=x|B=y', '--participants', 'architect' ], qr/2 or 3 roles/],
    ['four participants',  [ '--trigger', 'dispute', '--question', 'q?', '--evidence', 'e', '--options', 'A=x|B=y', '--participants', 'architect,reviewer,researcher,ux-designer' ], qr/2 or 3 roles/],
    ['no architect',       [ '--trigger', 'dispute', '--question', 'q?', '--evidence', 'e', '--options', 'A=x|B=y', '--participants', 'reviewer,researcher' ], qr/Architect decides/],
    ['an unknown role',    [ '--trigger', 'dispute', '--question', 'q?', '--evidence', 'e', '--options', 'A=x|B=y', '--participants', 'architect,wizard' ], qr/unknown role/],
    ['a repeated role',    [ '--trigger', 'dispute', '--question', 'q?', '--evidence', 'e', '--options', 'A=x|B=y', '--participants', 'architect,architect' ], qr/twice/],
    ['a long question',    [ '--trigger', 'dispute', '--question', words(61), '--evidence', 'e', '--options', 'A=x|B=y', '--participants', 'architect,reviewer' ], qr/60 words/],
) {
    ($rc, $out) = dt('discuss', 'new', @{ $case->[1] });
    isnt($rc, 0, "refused: $case->[0]");
    like($out, $case->[2], "  and says why: $case->[0]");
}
ok(!grep({ /discussion_open/ } ledger()), 'nothing was recorded by the refusals');

fresh();
dt('goal', 'lane', 'tiny');
($rc, $out) = open_one();
isnt($rc, 0, 'the tiny lane holds no discussion');
like($out, qr/tiny lane runs no agents/, 'and says so');
new_repo();
dt('init');
($rc, $out) = open_one();
isnt($rc, 0, 'no goal, no discussion');
dt('state', 'set', 'adhoc=true');
($rc, $out) = open_one(trigger => 'dispute');
isnt($rc, 0, 'an ad hoc session may debate only when the user asked');
($rc, $out) = open_one(trigger => 'user');
is($rc, 0, 'a debate the user asked for runs with no goal') or diag $out;
like($out, qr/adhoc-D1 opened \(user\)/, 'its id carries no goal');

# --- the record ---
fresh();
($rc, $out) = open_one();
is($rc, 0, 'a dispute opens') or diag $out;
like($out, qr/discussion G-001-D1 opened \(dispute\): at most 2 rounds, 150 words a statement/, 'it states the caps');
ok(-f "$REPO/.devteam/discussions/G-001-D1.md", 'the readable record exists');
ok(-f "$REPO/.devteam/discussions.json", 'and the state is a file agents cannot write');
my $md = slurp("$REPO/.devteam/discussions/G-001-D1.md");
like($md, qr/- A: Keep it in the client\n- B: Move it to the worker\n- NEW: none of these/, 'the options are listed, with a way out');
like($md, qr/Participants: architect, reviewer/, 'and the participants');
my ($open) = grep { /discussion_open/ } ledger();
is(decode_json($open)->{trigger}, 'dispute', 'the ledger records which trigger fired');
($rc, $out) = open_one();
isnt($rc, 0, 'one open discussion at a time');
like($out, qr/G-001-D1 is still open/, 'and names it');

# --- statements: positions, words, who may speak, in which round ---
($rc, $out) = dt('discuss', 'say', 'G-001-D1', 'researcher', '--position', 'A', '--text', 'hello');
isnt($rc, 0, 'a role that is not a participant cannot speak');
($rc, $out) = dt('discuss', 'say', 'G-001-D1', 'reviewer', '--position', 'Z', '--text', 'hello');
isnt($rc, 0, 'a position must be an option');
($rc, $out) = dt('discuss', 'say', 'G-001-D1', 'reviewer', '--position', 'B', '--text', words(151));
isnt($rc, 0, '151 words is over the cap');
like($out, qr/151 words; a statement is at most 150/, 'and says by how much');
($rc, $out) = dt('discuss', 'say', 'G-001-D1', 'reviewer', '--position', 'B', '--text', words(150));
is($rc, 0, '150 words is allowed') or diag $out;
($rc, $out) = dt('discuss', 'say', 'G-001-D1', 'reviewer', '--position', 'B', '--text', 'twice');
isnt($rc, 0, 'a participant speaks once a round');
($rc, $out) = dt('discuss', 'decide', 'G-001-D1');
isnt($rc, 0, 'no decision before round 1 is complete');
like($out, qr/round 1 is not complete.*architect/, 'and it says who is missing');

# --- consensus ends it early, the Architect's position is the decision, an ADR is written ---
($rc, $out) = dt('discuss', 'say', 'G-001-D1', 'architect', '--position', 'B', '--text', 'The worker already dedupes by job id.');
is($rc, 0, 'the Architect speaks');
like($out, qr/everyone agrees|all agree on B/, 'all agree: no second round is offered');
($rc, $out) = dt('discuss', 'say', 'G-001-D1', 'reviewer', '--position', 'A', '--text', 'second thoughts');
isnt($rc, 0, 'a second round after consensus is refused');
($rc, $out) = dt('discuss', 'decide', 'G-001-D1');
is($rc, 0, 'decide') or diag $out;
like($out, qr/^decided: B: Move it to the worker\nno dissent\. ADR: \.devteam\/adr\/0001-keep-the-retry-loop/m, 'the decision, no dissent, the ADR path');
my ($adr) = glob("$REPO/.devteam/adr/0001-*.md");
ok($adr, 'the ADR file exists');
my $a = slurp($adr);
like($a, qr/^# ADR-0001: Keep the retry loop/m, 'it has a number and the question');
like($a, qr/- A: Keep it in the client\n- B: Move it to the worker/, 'it names the options');
like($a, qr/^Decision: B: Move it to the worker$/m, 'the decision');
like($a, qr/^Dissent: none$/m, 'and that nobody dissented');
like($a, qr/Rounds: 1 of 2/, 'and the rounds used');
($rc, $out) = dt('discuss', 'say', 'G-001-D1', 'architect', '--position', 'A', '--text', 'late');
isnt($rc, 0, 'a decided discussion takes no more statements');
my ($close) = grep { /discussion_close/ } ledger();
is(decode_json($close)->{outcome}, 'decided', 'the ledger records the decision');

# --- a split: round 2, a changed mind or a held position, dissent kept with its words ---
fresh();
dt('discuss', 'new', '--trigger', 'options', @new[ 0 .. 5 ], '--options', 'A=Keep it in the client|B=Move it to the worker|C=Drop retries', '--participants', 'architect,reviewer,fullstack-engineer');
dt('discuss', 'say', 'G-001-D1', 'fullstack-engineer', '--position', 'A', '--source', 'reply', '--text', 'The client owns the timeout.');
($rc, $out) = dt('discuss', 'say', 'G-001-D1', 'fullstack-engineer', '--position', 'A', '--text', 'again');
isnt($rc, 0, 'an engineer cannot speak twice');
dt('discuss', 'say', 'G-001-D1', 'reviewer', '--position', 'B', '--text', 'The worker dedupes.');
($rc, $out) = dt('discuss', 'say', 'G-001-D1', 'architect', '--position', 'A', '--text', 'Keep it: moving it adds a hop.');
is($rc, 0, 'the Architect holds A');
like($out, qr/split \(A: architect, fullstack-engineer; B: reviewer\)/, 'a split is reported by position');
like($out, qr/the Architect's position stands/, 'with the cheap way out');
($rc, $out) = dt('discuss', 'brief', 'G-001-D1', 'reviewer');
like($out, qr/round 2 of 2/, 'the brief is for round 2');
like($out, qr/other statements are in it: answer them/, 'and points at the file');
like($out, qr/POSITION: A \| B \| C \| NEW/, 'it fixes the reply shape');
like($out, qr/Change no file, state or git, and start no other agent/, 'and keeps the participant read-only');
($rc, $out) = dt('discuss', 'say', 'G-001-D1', 'fullstack-engineer', '--position', 'B', '--source', 'reply', '--text', 'late');
isnt($rc, 0, 'a reply on hand stands in for round 1 only');
($rc, $out) = dt('discuss', 'say', 'G-001-D1', 'reviewer', '--position', 'B', '--text', 'The worker dedupes by job id (worker.py:40).');
is($rc, 0, 'the reviewer holds B in round 2');
($rc, $out) = dt('discuss', 'decide', 'G-001-D1');
isnt($rc, 0, 'a half-done round 2 is not decided over');
($rc, $out) = dt('discuss', 'say', 'G-001-D1', 'architect', '--position', 'A', '--text', 'Still A: a hop costs more than the double retry.');
like($out, qr/rounds are used|rounds? (?:is|are) used/, 'the second round used the cap');
($rc, $out) = dt('discuss', 'say', 'G-001-D1', 'reviewer', '--position', 'B', '--text', 'a third round');
isnt($rc, 0, 'there is no third round');
like($out, qr/2 rounds are used/, 'and it says so');
($rc, $out) = dt('discuss', 'decide', 'G-001-D1');
is($rc, 0, 'decide after round 2');
like($out, qr/^decided: A: Keep it in the client\ndissent: reviewer \(B\)/m, 'the Architect decides; the reviewer dissents');
($adr) = glob("$REPO/.devteam/adr/0001-*.md");
$a = slurp($adr);
like($a, qr/- reviewer wanted B: The worker dedupes by job id \(worker\.py:40\)\./, 'the dissent is kept with its last words');
like($a, qr/Rounds: 2 of 2/, 'two rounds');
like(slurp("$REPO/.devteam/discussions/G-001-D1.md"), qr/## Decision\nA: Keep it in the client/, 'the record ends with the decision');

# a new ADR takes the next number
new_repo();
dt('init'); dt('engage', 's1'); dt('goal', 'new', 'x'); dt('criteria', 'add', '--id', 'C1', '--text', 'WHEN x THEN y', '--check', 'true');
dt('goal', 'confirm', '--lane', 'standard', '--lifecycle', 'agile-kanban');
mkdir "$REPO/.devteam/adr";
open my $fh, '>', "$REPO/.devteam/adr/007-earlier-choice.md" or die; print $fh "# ADR-007\n"; close $fh;
open_one();
dt('discuss', 'say', 'G-001-D1', 'architect', '--position', 'A', '--text', 'x');
dt('discuss', 'say', 'G-001-D1', 'reviewer', '--position', 'A', '--text', 'x');
($rc, $out) = dt('discuss', 'decide', 'G-001-D1');
like($out, qr{\.devteam/adr/0008-}, 'the ADR number follows the highest one there is');

# --- a view on record whose owner never took part is kept as dissent without hand-editing anything ---
fresh();
open_one();
dt('discuss', 'say', 'G-001-D1', 'reviewer', '--position', 'A', '--text', 'a');
dt('discuss', 'say', 'G-001-D1', 'architect', '--position', 'A', '--text', 'a');
($rc, $out) = dt('discuss', 'decide', 'G-001-D1', '--dissent', 'Sam (engineer): Use SQLite; a JSON file means a rewrite in a month.');
is($rc, 0, 'decide takes a dissent from outside the participants') or diag $out;
like($out, qr/^dissent: Sam \(engineer\)\.? ?ADR/m, 'it is listed') or diag $out;
($adr) = glob("$REPO/.devteam/adr/0001-*.md");
like(slurp($adr), qr/^- Sam \(engineer\): Use SQLite; a JSON file means a rewrite in a month\.$/m, 'and kept in the ADR in their words');
like(slurp("$REPO/.devteam/discussions/G-001-D1.md"), qr/^- Sam \(engineer\): Use SQLite/m, 'and in the record');
fresh();
open_one();
dt('discuss', 'say', 'G-001-D1', 'reviewer', '--position', 'A', '--text', 'a');
dt('discuss', 'say', 'G-001-D1', 'architect', '--position', 'A', '--text', 'a');
($rc, $out) = dt('discuss', 'decide', 'G-001-D1', '--dissent', 'no colon here');
isnt($rc, 0, 'a dissent names who it is from');
($rc, $out) = dt('discuss', 'decide', 'G-001-D1', '--dissent', 'Sam: ' . words(151));
isnt($rc, 0, 'and is held to the word cap');

# the ADR file name ends on a whole word
fresh();
dt('discuss', 'new', '--trigger', 'user', '--question', 'Persist the todo list in a JSON file or in SQLite for the next quarter?',
    '--evidence', 'asked', '--options', 'A=JSON|B=SQLite', '--participants', 'architect,reviewer');
dt('discuss', 'say', 'G-001-D1', 'architect', '--position', 'A', '--text', 'x');
dt('discuss', 'say', 'G-001-D1', 'reviewer', '--position', 'A', '--text', 'x');
($rc, $out) = dt('discuss', 'decide', 'G-001-D1');
my ($slugged) = glob("$REPO/.devteam/adr/0001-*.md");
like($slugged, qr{0001-persist-the-todo-list-in-a-json-file-or-in\.md$}, 'the name is at most 48 characters and ends on a whole word') or diag $slugged;

# --- NEW: none of the options ---
fresh();
open_one();
dt('discuss', 'say', 'G-001-D1', 'reviewer', '--position', 'A', '--text', 'a');
dt('discuss', 'say', 'G-001-D1', 'architect', '--position', 'NEW', '--text', 'Put retries in a shared helper both call.');
($rc, $out) = dt('discuss', 'decide', 'G-001-D1');
like($out, qr/^decided: a new option: Put retries in a shared helper/m, 'the Architect may name a third way');
like($out, qr/dissent: reviewer \(A\)/, 'and the reviewer who wanted A dissents');

# --- caps per goal, cancel, close ---
fresh();
open_one();
dt('discuss', 'cancel', 'G-001-D1', '--reason', 'the user decided');
($rc, $out) = open_one();
is($rc, 0, 'a cancelled discussion frees the slot') or diag $out;
dt('discuss', 'cancel', 'G-001-D2', '--reason', 'moot');
($rc, $out) = open_one();
is($rc, 0, 'a cancelled discussion does not count toward the cap') or diag $out;
dt('discuss', 'say', 'G-001-D3', 'architect', '--position', 'A', '--text', 'x');
dt('discuss', 'say', 'G-001-D3', 'reviewer', '--position', 'A', '--text', 'x');
dt('discuss', 'decide', 'G-001-D3');
($rc, $out) = open_one();
is($rc, 0, 'one decided discussion is under the cap of two') or diag $out;
dt('discuss', 'say', 'G-001-D4', 'architect', '--position', 'A', '--text', 'x');
dt('discuss', 'say', 'G-001-D4', 'reviewer', '--position', 'A', '--text', 'x');
dt('discuss', 'decide', 'G-001-D4');
($rc, $out) = open_one();
isnt($rc, 0, 'a third held discussion is refused');
like($out, qr/held 2 discussions already/, 'with the cap named');

fresh();
open_one();
dt('state', 'transition', 'VERIFYING');
($rc, $out) = dt('close');
isnt($rc, 0, 'dt close waits for an open discussion');
like($out, qr/discussion G-001-D1 is still open: dt discuss decide G-001-D1, or dt discuss cancel/, 'and says what to do');
($rc, $out) = dt('discuss', 'cancel', 'G-001-D1');
isnt($rc, 0, 'cancel needs a reason');
dt('discuss', 'cancel', 'G-001-D1', '--reason', 'not needed');
($rc, $out) = dt('close');
is($rc, 0, 'with it cancelled the goal closes') or diag $out;

# --- the spawn cap and the status line ---
fresh();
update_spawns(10);
($rc, $out) = open_one();
isnt($rc, 0, 'with no spawns left there is no discussion');
like($out, qr/no spawns left \(10\/10\)/, 'and the cap is named');
sub update_spawns {
    my ($n) = @_;
    my $s = state();
    $s->{spawns} = $n;
    open my $h, '>', "$REPO/.devteam/state.json" or die;
    print $h encode_json($s);
    close $h;
    dt('resync');
}
fresh();
open_one();
($rc, $out) = dt('status');
like($out, qr/^discussion: G-001-D1 open, round 1 of 2/m, 'dt status shows an open discussion');

# --- the closure report prices the discussion from the ledger ---
fresh();
open_one();
open my $lg, '>>', "$REPO/.devteam/log.jsonl" or die;
for my $r (['architect', 100, 40], ['reviewer', 50, 20]) {
    print $lg qq({"event":"subagent_stop","agent_type":"devteam:$r->[0]","tokens":{"claude-sonnet-5-5":{"input":$r->[1],"output":$r->[2],"cache_read":1000,"cache_write":300}},"ts":"x"}\n);
}
close $lg;
dt('discuss', 'say', 'G-001-D1', 'architect', '--position', 'B', '--text', 'a');
dt('discuss', 'say', 'G-001-D1', 'reviewer', '--position', 'A', '--text', 'b');
dt('discuss', 'decide', 'G-001-D1');
open $lg, '>>', "$REPO/.devteam/log.jsonl" or die;
print $lg qq({"event":"subagent_stop","agent_type":"devteam:qa-engineer","tokens":{"claude-sonnet-5-5":{"input":999,"output":999}},"ts":"x"}\n);
close $lg;
dt('state', 'transition', 'VERIFYING');
($rc, $out) = dt('close');
is($rc, 0, 'the goal closes') or diag $out;
like(slurp("$REPO/.devteam/goals/G-001/closure.md"),
    qr/^discussion: G-001-D1 \(dispute\) decided B in 1 round\(s\), dissent: reviewer; 2 spawn\(s\) \(in=150 out=60 cache_read=2000 cache_write=600\)$/m,
    'the closure report names the decision, the dissent and what the two spawns cost, and not the later spawn');

# --- no goal runs a discussion unless a trigger fired: a plain goal has none in its ledger ---
fresh();
dt('state', 'transition', 'VERIFYING');
dt('close');
unlike(slurp("$REPO/.devteam/goals/G-001/closure.md"), qr/discussion:/, 'a goal without a trigger has no discussion line');
ok(!grep({ /discussion_/ } ledger()), 'and no discussion event in its ledger');

# --- the spawn guard lets a one-off consult or debate start with no goal, and only then ---
new_repo();
dt('init');
dt('engage', 's1');
sub spawn { hook('guard', { session_id => 's1', hook_event_name => 'PreToolUse', tool_name => 'Agent', tool_input => { subagent_type => $_[0] } }) }
($c, $o2) = spawn('devteam:architect');
is(decision($o2), 'deny', 'with no goal and no adhoc flag an agent is refused');
dt('state', 'set', 'adhoc=true');
($c, $o2) = spawn('devteam:architect');
is($o2, '', 'with adhoc set, a one-off consult starts (what /devteam:ask relies on; found live)');
dt('state', 'set', 'adhoc=false');
($c, $o2) = spawn('devteam:architect');
is(decision($o2), 'deny', 'and clearing the flag closes it again');

# --- authority: a subagent cannot run dt discuss; discussion state is not writable by agents ---
fresh();
($c, $o2) = hook('git-guard', { session_id => 's1', cwd => $REPO, agent_id => 'a1', agent_type => 'devteam:reviewer', tool_name => 'Bash',
    tool_input => { command => 'dt discuss say G-001-D1 reviewer --position A --text hi' } });
is(decision($o2), 'deny', 'a subagent cannot record a statement itself');
($c, $o2) = hook('state-protect', { session_id => 's1', cwd => $REPO, agent_id => 'a1', agent_type => 'devteam:architect', tool_name => 'Write',
    tool_input => { file_path => "$REPO/.devteam/discussions.json", content => '{}' } });
is(decision($o2), 'deny', 'nor write the discussion state');
($c, $o2) = hook('state-protect', { session_id => 's1', cwd => $REPO, agent_id => 'a1', agent_type => 'devteam:architect', tool_name => 'Write',
    tool_input => { file_path => "$REPO/.devteam/adr/0001-x.md", content => 'x' } });
is($o2, '', 'the Architect may still write an ADR');

# --- the written parts ---
my $skill = slurp("$PLUGIN/skills/discuss/SKILL.md");
cmp_ok(scalar(() = $skill =~ /\n/g), '<=', 30, 'the skill is short');
like($skill, qr/`dispute`.*`options`.*`user`/s, 'it lists the three triggers');
like($skill, qr/Never.*security FIX.*criterion or scope change.*tiny lane/s, 'and what a discussion is never for');
like($skill, qr/Agents never message each other/, 'the PM carries every statement');
like($skill, qr/there is no third/, 'two rounds');
my $o = slurp("$PLUGIN/skills/orchestrate/SKILL.md");
like($o, qr/Only three things start a discussion.*`dispute`.*`options`.*`user`/s, 'orchestrate names the triggers and points at the skill');
like(slurp("$PLUGIN/agents/architect.md"), qr/`CONTESTED:` line.*your final position there decides/s, 'the Architect flags a contested choice and knows it decides');
like(slurp("$PLUGIN/skills/ask/SKILL.md"), qr/`\/devteam:ask debate <question>`.*trigger `user`/s, 'the user asks for a debate through /devteam:ask');

done_testing;
