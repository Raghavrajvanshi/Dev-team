use strict;
use warnings;
use FindBin;
use JSON::PP;
use Test::More;
require "$FindBin::Bin/lib.pl";
our ($PLUGIN, $REPO);

sub slurp { open my $h, '<', $_[0] or return ''; local $/; <$h> }
sub records { [ map { decode_json($_) } grep { /\S/ } split /\n/, slurp("$REPO/.devteam/trace.jsonl") ] }
sub spawn { hook('guard', { session_id => 's1', hook_event_name => 'PreToolUse', tool_name => 'Agent', tool_input => { subagent_type => 'devteam:architect', %{ $_[0] // {} } } }) }

new_repo();
dt('init');
dt('engage', 's1');
dt('goal', 'new', 'trace');
dt('criteria', 'add', '--id', 'C1', '--text', 'WHEN x THEN y', '--check', 'true');
dt('goal', 'confirm', '--lane', 'standard', '--lifecycle', 'direct');
my ($rc, $out);

# --- off by default: nothing is recorded ---
spawn();
ok(!-e "$REPO/.devteam/trace.jsonl", 'tracing is off by default and writes nothing');
($rc, $out) = dt('trace', 'status');
like($out, qr/trace: off, 0 record/, 'status says off');

# --- on: input and decision are recorded ---
dt('trace', 'on');
spawn({ model => 'haiku', effort => 'low', prompt => 'x' x 500 });
my $r = records();
my ($in) = grep { $_->{input} } @$r;
is($in->{handler}, 'guard', 'the handler is named');
is($in->{event}, 'PreToolUse', 'and its event');
is($in->{owned}, 1, 'ownership is recorded');
is($in->{input}{tool_input}{subagent_type}, 'devteam:architect', 'the raw tool input is kept');
like($in->{input}{tool_input}{prompt}, qr/\.\.\.\(500 chars\)$/, 'long strings are truncated');
ok(grep({ exists $_->{decision} } @$r), 'the decision is recorded');
($rc, $out) = dt('trace', 'show');
like($out, qr/guard\s+PreToolUse\s+agent=0 owned=1 keys=/, 'show lists records compactly');

# --- other sessions and subagents are recorded with their flags ---
hook('guard', { session_id => 'OTHER', hook_event_name => 'PreToolUse', tool_name => 'Agent', tool_input => { subagent_type => 'devteam:qa-engineer' } });
hook('state-protect', { session_id => 's1', hook_event_name => 'PreToolUse', tool_name => 'Write', tool_input => { file_path => 'x' }, agent_id => 'a1', agent_type => 'devteam:fullstack-engineer' });
$r = records();
ok(grep({ ($_->{input}{session_id} // '') eq 'OTHER' && ($_->{owned} // 1) == 0 } @$r), 'a foreign session is recorded as not owned');
ok(grep({ ($_->{handler} // '') eq 'state-protect' && ($_->{agent} // 0) == 1 } @$r), 'a subagent call is recorded as an agent call');

# --- env switch works without config; hook.sh keeps the trace handler cheap ---
dt('trace', 'off');
dt('trace', 'clear');
{
    my $plug = "$FindBin::Bin/../plugins/devteam";
    ($rc, $out) = sh("CLAUDE_PROJECT_DIR=$REPO sh $plug/hooks/hook.sh trace < /dev/null");
    ok(!-e "$REPO/.devteam/trace.jsonl", 'the trace-only handler records nothing while tracing is off');
    sh(qq{echo '{"session_id":"s1","hook_event_name":"SubagentStart","agent_id":"a9","agent_type":"devteam:architect"}' | DT_TRACE=1 CLAUDE_PROJECT_DIR=$REPO DT_ROOT=$REPO sh $plug/hooks/hook.sh trace});
    $r = records();
    is($r->[0]{event}, 'SubagentStart', 'DT_TRACE=1 records SubagentStart through the trace handler');
}

# --- report: verdicts from synthetic records ---
dt('trace', 'clear');
open my $f, '>', "$REPO/.devteam/trace.jsonl" or die;
my @lines = (
    { handler => 'guard', event => 'PreToolUse', agent => 0, owned => 1, input => { tool_name => 'Agent', tool_input => { subagent_type => 'devteam:architect', model => 'haiku', effort => 'low' } } },
    { handler => 'state-protect', event => 'PreToolUse', agent => 1, owned => 1, input => { agent_id => 'a1', agent_type => 'devteam:fullstack-engineer', tool_name => 'Write' } },
    { handler => 'finish-gate', event => 'SubagentStop', agent => 1, owned => 1, input => { agent_id => 'a1', agent_type => 'devteam:fullstack-engineer', last_assistant_message => 'x' } },
    { handler => 'trace', event => 'SubagentStart', agent => 1, owned => 1, input => { agent_id => 'a1', agent_type => 'devteam:fullstack-engineer' } },
    { handler => 'finish-gate', decision => { exit => 2, retry => 1 } },
    { handler => 'compact-reinject', event => 'SessionStart', agent => 0, owned => 1, input => { source => 'compact' } },
    { kind => 'note', id => 'dt-on-path', verdict => 'confirmed', text => 'command -v dt found it' },
);
print $f encode_json($_), "\n" for @lines;
close $f;
($rc, $out) = dt('trace', 'report');
like($out, qr/^confirmed\s+agent-input-fields\s+.*subagent_type/m, 'agent input fields confirmed');
like($out, qr/^confirmed\s+agent-id-on-subagent-calls/m, 'agent_id confirmed from a subagent tool call');
like($out, qr/^confirmed\s+agent-type-values\s+values seen: devteam:fullstack-engineer/m, 'agent_type values confirmed with the prefix');
like($out, qr/^info\s+model-effort-passed\s+.*devteam:architect model=haiku effort=low/m, 'model and effort passed are listed');
like($out, qr/^confirmed\s+session-start-sources\s+sources seen: compact/m, 'compact SessionStart seen');
like($out, qr/^info\s+finish-gate-blocked\s+1 finish-gate block.*not known to be honoured/m, 'a block with no later stop is counted but not claimed as honoured');
like($out, qr/^confirmed\s+dt-on-path/m, 'a manual note becomes a verdict');
like($out, qr/^unseen\s+skills-preload/m, 'a manual check without a note stays unseen');

# a block followed by another stop from the same agent is proof the gate was honoured (seen live on 12 October 2026)
open $f, '>', "$REPO/.devteam/trace.jsonl" or die;
print $f encode_json($_), "\n" for (
    { handler => 'finish-gate', event => 'SubagentStop', agent => 1, owned => 1, input => { agent_id => 'a1', agent_type => 'devteam:fullstack-engineer' } },
    { handler => 'finish-gate', decision => { exit => 2, retry => 1 } },
    { handler => 'finish-gate', event => 'SubagentStop', agent => 1, owned => 1, input => { agent_id => 'a1', agent_type => 'devteam:fullstack-engineer' } },
    { handler => 'finish-gate', decision => 'none' },
);
close $f;
($rc, $out) = dt('trace', 'report');
like($out, qr/^confirmed\s+finish-gate-blocked\s+1 finish-gate block\(s\) issued, and the agent stopped again/m, 'a block followed by another stop is confirmed as honoured');

# --- verdicts that matter when things are wrong ---
open $f, '>', "$REPO/.devteam/trace.jsonl" or die;
print $f encode_json($_), "\n" for (
    { handler => 'guard', event => 'PreToolUse', agent => 0, owned => 1, input => { tool_name => 'Agent', tool_input => { prompt => 'p' } } },
    { handler => 'git-guard', event => 'PreToolUse', agent => 0, owned => 1, input => { tool_name => 'Bash' } },
    { handler => 'ledger', event => 'SubagentStop', agent => 1, owned => 1, input => { agent_id => 'a2', agent_type => 'fullstack-engineer' } },
);
close $f;
($rc, $out) = dt('trace', 'report');
like($out, qr/^refuted\s+agent-input-fields/m, 'a spawn without subagent_type is refuted');
like($out, qr/^suspect\s+agent-id-on-subagent-calls/m, 'spawns and tool calls but no agent_id is suspect');
like($out, qr/^refuted\s+agent-type-values\s+values seen: fullstack-engineer .*expects the devteam: prefix/m, 'bare agent_type values are refuted, with the reason');

# --- notes are validated ---
($rc, $out) = dt('trace', 'note', 'x', 'maybe');
isnt($rc, 0, 'a note needs confirmed, refuted or unseen');
($rc, $out) = dt('trace', 'note', 'skills-preload', 'refuted', 'agent said NOT LOADED');
is($rc, 0, 'a valid note is accepted');
done_testing;
