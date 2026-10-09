use strict;
use warnings;
use FindBin;
use JSON::PP;
use Test::More;
require "$FindBin::Bin/lib.pl";
our $REPO;

new_repo();
my ($rc, $out);
sub decision { my $j = eval { decode_json($_[0]) } or return ''; $j->{hookSpecificOutput}{permissionDecision} // '' }
sub reason   { my $j = eval { decode_json($_[0]) } or return ''; $j->{hookSpecificOutput}{permissionDecisionReason} // '' }
sub spawn    { my %a = @_; hook('guard', { session_id => 's1', hook_event_name => 'PreToolUse', tool_name => 'Agent', tool_input => { subagent_type => $a{type}, %{ $a{extra} // {} } }, ($a{agent} ? (agent_id => 'a1', agent_type => 'devteam:architect') : ()) }) }
sub agent_in { my %a = @_; { session_id => 's1', cwd => $REPO, agent_id => $a{id} // 'a1', agent_type => $a{role} // 'devteam:fullstack-engineer', %a } }

# --- not engaged: every hook is silent (and hook.sh does not even start perl) ---
dt('init');
($rc, $out) = spawn(type => 'devteam:architect');
is($out, '', 'not engaged: guard stays silent');
{
    my $plug = "$FindBin::Bin/../plugins/devteam";
    ($rc, $out) = sh("CLAUDE_PROJECT_DIR=$REPO sh $plug/hooks/hook.sh guard < /dev/null");
    is_deeply([$rc, $out], [0, ''], 'hook.sh exits silently when not engaged');
}

dt('engage', 's1');
# --- IDLE ---
is(decision((spawn(type => 'devteam:architect'))[1]), 'deny', 'IDLE: devteam agents are denied');
is((spawn(type => 'Explore'))[1], '', 'IDLE: ordinary agents are untouched');

# --- INTAKE ---
dt('goal', 'new', 'demo');
is(decision((spawn(type => 'devteam:architect'))[1]), 'deny', 'INTAKE: no agents before the goal is confirmed');
like(reason((spawn(type => 'Explore'))[1]), qr/INTAKE/, 'INTAKE: even ordinary agents are blocked, with the reason');

# --- ACTIVE (standard lane, cap 5, no worktree grant) ---
dt('criteria', 'add', '--id', 'C1', '--text', 'WHEN x THEN y', '--check', 'true');
dt('goal', 'confirm', '--lane', 'standard', '--lifecycle', 'agile-kanban', '--grants', 'integration');
is((spawn(type => 'devteam:architect'))[1], '', 'ACTIVE: a devteam agent is allowed');
is(state()->{spawns}, 1, 'spawn is counted');
is(decision((spawn(type => ''))[1]), 'deny', 'ACTIVE: untyped agent/fork is denied');
is(decision((spawn(type => 'general-purpose'))[1]), 'deny', 'ACTIVE: general-purpose is denied');
is((spawn(type => 'Explore'))[1], '', 'ACTIVE: Explore is allowed and not counted');
is(state()->{spawns}, 1, 'Explore did not count');
is(decision((spawn(type => 'devteam:fullstack-engineer', extra => { isolation => 'worktree' }))[1]), 'deny', 'worktree needs the task_branches grant');
is(decision((spawn(type => 'devteam:architect', agent => 1))[1]), 'deny', 'agents cannot spawn agents');
spawn(type => 'devteam:qa-engineer') for 1 .. 3;
spawn(type => 'devteam:reviewer');
is(state()->{spawns}, 5, 'five spawns counted');
like(reason((spawn(type => 'devteam:reviewer'))[1]), qr/spawn cap reached \(5\/5/, 'the sixth is refused at the cap');

# --- another session is ignored for main-thread events ---
($rc, $out) = hook('guard', { session_id => 'OTHER', tool_name => 'Agent', tool_input => { subagent_type => 'general-purpose' } });
is($out, '', 'a different session is not governed');

# --- state-protect ---
sub write_in { my ($f, %a) = @_; hook('state-protect', agent_in(tool_name => 'Write', tool_input => { file_path => $f }, %a)) }
is(decision((write_in("$REPO/.devteam/state.json"))[1]), 'deny', 'subagent cannot write state.json');
is(decision((write_in(".devteam/goals/G-001/criteria.json"))[1]), 'deny', 'relative path to criteria.json is denied');
is(decision((write_in("$REPO/.devteam/goals/../goals/G-001/board.md"))[1]), 'deny', 'path tricks are normalised');
is((write_in("$REPO/.devteam/adr/0001.md"))[1], '', 'ADRs are allowed');
is((write_in("$REPO/.devteam/goals/G-001/design.md"))[1], '', 'design.md is allowed');
is((write_in("$REPO/src/app.js"))[1], '', 'ordinary source files are untouched');
is((hook('state-protect', { session_id => 's1', tool_name => 'Write', tool_input => { file_path => "$REPO/.devteam/state.json" } }))[1], '', 'the main thread is not restricted');
sh('echo t > test_a.t && git add test_a.t && git commit -q -m t');
dt('criteria', 'lock', 'test_a.t');
is(decision((write_in("$REPO/test_a.t"))[1]), 'deny', 'locked acceptance test: engineer denied');
is((write_in("$REPO/test_a.t", agent_type => 'devteam:qa-engineer'))[1], '', 'locked acceptance test: QA allowed');
is(decision((write_in("$REPO/.claude/worktrees/w1/test_a.t"))[1]), 'deny', 'the lock follows into a worktree path');

# --- git-guard ---
sub git { my ($cmd, %a) = @_; hook('git-guard', agent_in(tool_name => 'Bash', tool_input => { command => $cmd }, %a)) }
is((git('git status && git diff'))[1], '', 'read git is open to everyone');
is((git('ls -la', role => 'devteam:reviewer'))[1], '', 'non-git commands are untouched');
is(decision((git('git push origin main'))[1]), 'deny', 'push is denied for agents');
is(decision((git('gh pr create --title x'))[1]), 'deny', 'PR creation is denied for agents');
is(decision((git('git reset --hard'))[1]), 'deny', 'destructive git is denied');
is(decision((git('sh -c "git push"'))[1]), 'deny', 'unverifiable git is denied');
is(decision((git('git commit -m x', role => 'devteam:reviewer'))[1]), 'deny', 'read-only roles cannot commit');
like(reason((git('git commit -m x'))[1]), qr/task_branches/, 'engineer without the grant is denied, and told why');
dt('grant', 'set', 'task_branches');
like(reason((git('git commit -m x'))[1]), qr/devteam\/\* or worktree-\*.*'main'/, 'a granted engineer still cannot commit on your branch');
sh('git switch -q -c devteam/G-001');
is((git('git add -A && git commit -m x'))[1], '', 'granted engineer may commit on a devteam branch');
is(decision((git('git checkout main'))[1]), 'deny', 'agents cannot switch branches');
is(decision((git('git commit -m x', role => 'devteam:architect'))[1]), 'deny', 'architect still read-only');
is((hook('git-guard', { session_id => 's1', tool_name => 'Bash', tool_input => { command => 'git push' } }))[1], '', 'the main thread is not governed by the hook');

# --- route ---
sub route { hook('route', { session_id => 's1', hook_event_name => 'UserPromptSubmit', prompt => $_[0] }) }
dt('state', 'transition', 'VERIFYING');
is((route('add a feature'))[1], '', 'ACTIVE/VERIFYING: no routing hint');
sh(q{perl -pi -e 's/"VERIFYING"/"ACTIVE"/' .devteam/state.json}); dt('resync');
dt('state', 'transition', 'STOPPED'); dt('state', 'transition', 'IDLE');
like((route('add a feature'))[1], qr/new goal/, 'IDLE: a plain prompt is treated as a new goal');
is((route('/devteam:status'))[1], '', 'slash commands are not hijacked');
is((route('<task-notification>agent done</task-notification>'))[1], '', 'agent reports are not treated as goals');

# --- finish-gate ---
dt('goal', 'new', 'gated');
dt('criteria', 'add', '--id', 'C1', '--text', 'WHEN x THEN y', '--check', 'true');
dt('goal', 'confirm', '--lane', 'standard', '--lifecycle', 'agile-kanban');
sh(q{perl -MJSON::PP -e 'open F,"<.devteam/config.json";local $/;$c=decode_json(<F>);$c->{gates}{test_affected}="echo BOOM; exit 3";open O,">.devteam/config.json";print O encode_json($c)'});
dt('resync');
sub stop { hook('finish-gate', agent_in(hook_event_name => 'SubagentStop', @_)) }
for my $n (1 .. 3) {
    ($rc, $out) = stop(id => 'e1');
    is($rc, 2, "failing gate blocks the agent from finishing (retry $n)");
}
like($out, qr/retry 3 of 3.*BOOM/s, 'the agent is told what failed');
($rc, $out) = stop(id => 'e1');
is($rc, 0, 'after the cap the agent is let go');
is(state()->{status}, 'BLOCKED', 'and the goal is BLOCKED for the user');
like(state()->{blocked_reason}, qr/gates still failing after 3 retries/, 'with the reason');
($rc, $out) = stop(id => 'r1', role => 'devteam:reviewer');
is_deeply([$rc, $out], [0, ''], 'read-only roles are not gated');

# --- tamper -> BLOCKED ---
dt('state', 'transition', 'ACTIVE');
sh(q{perl -pi -e 's/"passes" : false/"passes" : true/' .devteam/goals/G-002/criteria.json});
route('x');
hook('turn-count', { session_id => 's1', hook_event_name => 'Stop' });
is(state()->{status}, 'BLOCKED', 'editing criteria.json outside dt blocks the goal');
like(state()->{blocked_reason}, qr/changed outside dt/, 'and says so');

# --- turn-count and compact digest ---
dt('state', 'transition', 'ACTIVE');
dt('state', 'set', 'turn_cap=2', 'main_turns=0');
hook('turn-count', { session_id => 's1' });
($rc, $out) = hook('turn-count', { session_id => 's1' });
like($out, qr/systemMessage.*reached the standard lane cap/, 'turn cap warns exactly at the cap');
is(state()->{main_turns}, 2, 'turns counted');
($rc, $out) = hook('compact-reinject', { session_id => 's1', hook_event_name => 'SessionStart', source => 'compact' });
like($out, qr/devteam digest.*status=ACTIVE goal=G-002/s, 'compact re-injects a state digest');
($rc, $out) = hook('compact-reinject', { session_id => 's1', source => 'startup' });
is($out, '', 'but not on a normal start');

# --- ledger ---
open my $t, '>', "$REPO/../tr.jsonl" or die;
print $t encode_json({ message => { model => 'claude-sonnet-x', usage => { input_tokens => 10, output_tokens => 5, cache_read_input_tokens => 100 } } }), "\n";
print $t encode_json({ type => 'user' }), "\n";
close $t;
hook('ledger', { session_id => 's1', hook_event_name => 'Stop', transcript_path => "$REPO/../tr.jsonl" });
($rc, $out) = dt('ledger');
like($out, qr/main_stop: 1/, 'ledger counts the stop');
like($out, qr/claude-sonnet-x: in=10 out=5 cache_read=100/, 'ledger sums tokens by model');
hook('ledger', { session_id => 's1', hook_event_name => 'Stop', transcript_path => "$REPO/../tr.jsonl" });
($rc, $out) = dt('ledger');
like($out, qr/claude-sonnet-x: in=10 out=5/, 'a second read does not double-count');

done_testing;
