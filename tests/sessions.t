use strict;
use warnings;
use FindBin;
use JSON::PP;
use File::Temp qw(tempdir);
use Test::More;
require "$FindBin::Bin/lib.pl";
our $REPO;

# Other Claude sessions in the same repo: detection, the lease on the team, and the spawn guard.
new_repo();
my $CLAUDE = tempdir(CLEANUP => 1);
my $TRANS  = tempdir(CLEANUP => 1);
mkdir "$CLAUDE/sessions";
@ENV{qw(DT_CLAUDE_DIR DT_TRANSCRIPT_DIR)} = ($CLAUDE, $TRANS);
delete $ENV{DT_LIVE_SECS};
my ($rc, $out);
my ($ALIVE_A, $ALIVE_B, $ALIVE_C, $DEAD) = ($$, getppid(), ($^O =~ /^(?:msys|cygwin|MSWin32)$/ ? getppid() : 1), 2147483646);    # pid 1 answers EPERM: alive but not ours (there is no pid 1 under MSYS)
my $n = 100;
sub reg {    # a registry entry as Claude Code writes it
    my ($id, %f) = @_;
    my $e = { pid => $f{pid} // $ALIVE_A, sessionId => $id, cwd => $f{cwd} // $REPO, status => $f{status} // 'idle',
        updatedAt => (time - ($f{age} // 5)) * 1000, name => $f{name} // "name of $id", kind => 'interactive' };
    open my $h, '>', "$CLAUDE/sessions/" . ($n++) . '.json' or die;
    print $h encode_json($e);
    close $h;
}
sub clear_registry { unlink glob "$CLAUDE/sessions/*.json" }
sub others { my (undef, $o) = dt('sessions', '--self', 'S1'); $o }
sub guard {
    my ($sid, $type) = @_;
    hook('guard', { session_id => $sid, hook_event_name => 'PreToolUse', tool_name => 'Agent', tool_input => { subagent_type => $type } });
}
sub decision { my $j = eval { decode_json($_[0]) } or return ''; $j->{hookSpecificOutput}{permissionDecision} // '' }
sub reason   { my $j = eval { decode_json($_[0]) } or return ''; $j->{hookSpecificOutput}{permissionDecisionReason} // '' }

dt('init');

# --- detection from the registry ---
reg('S1', pid => $ALIVE_A, status => 'busy');                                    # this session
reg('S2', pid => $ALIVE_B, status => 'busy', age => 4000);                      # busy: live however long ago it updated
reg('S3', pid => $ALIVE_C, age => 100);                                          # idle but recent
reg('S4', pid => $ALIVE_A, age => 5000);                                         # idle for too long
reg('S5', pid => $DEAD, age => 1);                                               # process gone
reg('S6', pid => $ALIVE_A, cwd => '/somewhere/else', age => 1);                  # another project
reg('S7', pid => $ALIVE_A, cwd => "$REPO/.claude/worktrees/w1", age => 1);       # isolated worktree
reg('S8', pid => $ALIVE_A, cwd => "$REPO/sub", age => 1);                        # below the root: shares the tree
$out = others();
for my $live (qw(S2 S3 S8)) { like($out, qr/"name of $live"/, "registry: $live is a live session sharing the tree") }
for my $no (qw(S1 S4 S5 S6 S7)) { unlike($out, qr/"name of $no"/, "registry: $no is not listed") }
like($out, qr/sessions sharing this tree: 3/, 'registry: the count is right');

# --- an untrusted registry (it does not list us) falls back to transcripts ---
clear_registry();
reg('S2', pid => $ALIVE_B, age => 1);    # S1 is missing, so none of this is believed
for my $t (['T1', 60], ['T2', 5000]) {
    my $f = "$TRANS/$t->[0].jsonl";
    open my $h, '>', $f or die; close $h;
    utime(time - $t->[1], time - $t->[1], $f);
}
$out = others();
like($out, qr/T1.*seen via transcript/, 'fallback: a recent transcript is a live session');
unlike($out, qr/T2/, 'fallback: an old transcript is not');
unlike($out, qr/name of S2/, 'fallback: an untrusted registry is not believed');
($rc, $out) = dt('sessions', 'probe', '--self', 'S1');
like($out, qr/registry: not usable/, 'probe says the registry does not list this session');
unlink glob "$TRANS/*.jsonl";
clear_registry();

# --- engagement: others must be accepted, the lease must be respected ---
reg('S1', pid => $ALIVE_A);
reg('S2', pid => $ALIVE_B, status => 'busy', name => 'the other window');
($rc, $out) = dt('engage', 'S1');
is($rc, 2, 'engage: refuses until the user has chosen');
like($out, qr/ENGAGE NEEDS A CHOICE.*the other window.*--accept-others/s, 'engage: names the other session and the choice');
is(state()->{engaged}, JSON::PP::false, 'engage: nothing changed');
($rc, $out) = dt('engage', 'S1', '--accept-others');
is($rc, 0, 'engage: proceeds once the others are accepted') or diag $out;
is(state()->{owner_session}, 'S1', 'engage: this session owns the team');
is(do { local (@ARGV, $/) = "$REPO/.devteam/session.lock"; <> }, "S1\n", 'engage: the lease records the holder');

reg('S9', pid => $ALIVE_C);                       # a second window starts /devteam:start
($rc, $out) = dt('engage', 'S9', '--accept-others');
is($rc, 2, 'lease: a live holder is not taken over silently');
like($out, qr/another session holds the team: S1.*--take-over/s, 'lease: says who holds it and how to take it');
is(state()->{owner_session}, 'S1', 'lease: the holder is unchanged');
($rc, $out) = dt('engage', 'S9', '--take-over', '--accept-others');
is($rc, 0, 'lease: --take-over is the user choosing') or diag $out;
is(state()->{owner_session}, 'S9', 'lease: the new window holds the team');
is(do { local (@ARGV, $/) = "$REPO/.devteam/session.lock"; <> }, "S9\n", 'lease: the lock follows');

clear_registry();
reg('S1', pid => $ALIVE_A);
reg('S9', pid => $DEAD);                           # the window that held it has been closed
($rc, $out) = dt('engage', 'S1');
is($rc, 0, 'lease: a closed holder is taken over without a prompt') or diag $out;
like($out, qr/held the team earlier.*no longer running/, 'lease: and the user is told');

clear_registry();
reg('S1', pid => $ALIVE_A);                        # S1 holds it; S5 asks, and the registry lists S5 and S1 only
reg('S5', pid => $ALIVE_B);
dt('engage', 'S1');
clear_registry();
reg('S5', pid => $ALIVE_B);                        # S1 vanished from the registry, as after /clear
($rc, $out) = dt('engage', 'S5');
is($rc, 0, 'lease: a holder missing from a trusted registry (a cleared session) is not blocking') or diag $out;

# --- no registry at all: the heartbeat decides ---
clear_registry();
dt('engage', 'S5');                                # lease: S5, fresh
($rc, $out) = dt('engage', 'S6');
is($rc, 2, 'heartbeat: a fresh lease holds without a registry');
my $lock = "$REPO/.devteam/session.lock";
utime(time - 7200, time - 7200, $lock);
($rc, $out) = dt('engage', 'S6');
is($rc, 0, 'heartbeat: a stale lease is taken over') or diag $out;

# --- the spawn guard ---
dt('goal', 'new', 'guarded');
dt('criteria', 'add', '--id', 'C1', '--text', 'WHEN x THEN y', '--check', 'true');
dt('goal', 'confirm', '--lane', 'standard', '--lifecycle', 'agile-kanban');
clear_registry();
reg('S6', pid => $ALIVE_A);
reg('S2', pid => $ALIVE_B, status => 'busy', name => 'writer window');
($rc, $out) = guard('S6', 'devteam:architect');
is(decision($out), 'deny', 'guard: a spawn is refused while another live session is unacknowledged');
like(reason($out), qr/writer window.*dt sessions ack.*separate worktree/s, 'guard: the warning names it and offers the choices');
is(state()->{spawns}, 0, 'guard: a refused spawn is not counted');
($rc, $out) = dt('sessions', 'ack', '--self', 'S6');
like($out, qr/^acknowledged for G-001: S2$/m, 'ack: recorded for this goal');
($rc, $out) = guard('S6', 'devteam:architect');
is($out, '', 'guard: the spawn goes ahead once acknowledged');
is(state()->{spawns}, 1, 'guard: and is counted');
reg('S11', pid => $ALIVE_C, name => 'a newcomer');
($rc, $out) = guard('S6', 'devteam:architect');
is(decision($out), 'deny', 'guard: a session that appears later is a new warning');
like(reason($out), qr/a newcomer/, 'guard: naming only the new one');
unlike(reason($out), qr/writer window/, 'guard: and not the one already acknowledged');
dt('sessions', 'ack', 'S11', '--self', 'S6');
is((guard('S6', 'devteam:architect'))[1], '', 'guard: acknowledging by id works');

# --- a session that does not own the team ---
($rc, $out) = guard('S2', 'devteam:architect');
is(decision($out), 'deny', 'other session: cannot start devteam agents');
like(reason($out), qr/held by another session.*\/devteam:start/s, 'other session: told how to take the team');
is((guard('S2', 'Explore'))[1], '', 'other session: ordinary agents are left alone');
is((guard('S2', 'general-purpose'))[1], '', 'other session: general-purpose is not our business');
is(state()->{spawns}, 2, 'other session: nothing was counted against the owner');

# --- hooks remember what other sessions do, and the owner keeps the lease warm ---
hook('state-protect', { session_id => 'S2', hook_event_name => 'PreToolUse', tool_name => 'Write', tool_input => { file_path => "$REPO/tests/a.t" } });
my $store = decode_json(do { local (@ARGV, $/) = "$REPO/.devteam/sessions.json"; <> });
is($store->{seen}{S2}{writes}[0]{path}, "$REPO/tests/a.t", 'hooks: another session\'s write is recorded with its path');
($rc, $out) = dt('sessions', '--self', 'S6');
like($out, qr{tests/a\.t  by S2},  'sessions: lists the writes our hooks saw');
utime(time - 600, time - 600, $lock);
hook('route', { session_id => 'S6', hook_event_name => 'UserPromptSubmit', prompt => 'x' });
cmp_ok(time - (stat $lock)[9], '<', 60, 'heartbeat: the owner\'s activity touches the lock');
utime(time - 600, time - 600, $lock);
hook('route', { session_id => 'S2', hook_event_name => 'UserPromptSubmit', prompt => 'x' });
cmp_ok(time - (stat $lock)[9], '>', 300, 'heartbeat: another session does not');

# --- status shows it ---
($rc, $out) = dt('status');
like($out, qr/other live sessions: \d+/, 'status: shows other live sessions');

# --- subagents cannot touch any of this ---
for my $cmd ('dt sessions ack', 'dt scope accept --all', 'dt scope start T1 src/', 'dt engage S3 --take-over') {
    my ($r, $o) = hook('git-guard', { session_id => 'S6', hook_event_name => 'PreToolUse', tool_name => 'Bash', agent_id => 'a1',
        agent_type => 'devteam:fullstack-engineer', cwd => $REPO, tool_input => { command => $cmd } });
    is(decision($o), 'deny', "subagent cannot run: $cmd");
}

done_testing();
