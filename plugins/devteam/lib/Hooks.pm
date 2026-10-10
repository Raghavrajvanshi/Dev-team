package Hooks;
# Hook handlers. Each reads the hook input (a hashref), may print one JSON decision, and exits.
# Everything here is a no-op unless devteam is engaged for this project (see hooks/hook.sh).
use strict;
use warnings;
use JSON::PP;
use DT qw(root ddir slurp spit jread ts ledger_add state_read state_write update_state config_read check_seal seal
  goal_dir git_out run_gates usage_since locked);
use DT::Git qw(classify);
use Exporter 'import';
our @EXPORT_OK = qw(dispatch);

my $J = JSON::PP->new->canonical;
my %WRITER = map { ("devteam:$_" => 1) } qw(fullstack-engineer backend-engineer frontend-engineer
  mobile-engineer devops-engineer qa-engineer tech-writer);

# Trace: with DT_TRACE=1 or `dt trace on`, every hook records what it was given and what it decided,
# so assumptions about Claude Code can be settled from a real run (see `dt trace report`).
my ($TRACE, $CUR) = (0, '');
sub trace_on { $ENV{DT_TRACE} ? 1 : (config_read()->{trace} ? 1 : 0) }
sub shrink {
    my ($v, $d) = @_;
    $d //= 0;
    return '[...]' if $d > 4;
    if (ref $v eq 'HASH')  { my @k = sort keys %$v; return { map { $_ => shrink($v->{$_}, $d + 1) } @k[0 .. ($#k > 24 ? 24 : $#k)] } }
    if (ref $v eq 'ARRAY') { return [ map { shrink($_, $d + 1) } @$v[0 .. ($#$v > 9 ? 9 : $#$v)] ] }
    return $v if ref $v || !defined $v;
    my $str = "$v";
    return length($str) > 120 ? substr($str, 0, 120) . '...(' . length($str) . ' chars)' : $str;
}
sub trace {
    return unless $TRACE;
    my ($rec) = @_;
    @$rec{qw(ts handler)} = (ts(), $rec->{handler} // $CUR);
    if (open my $h, '>>', ddir() . '/trace.jsonl') { print $h $J->encode($rec), "\n"; close $h }
}

sub out     { trace({ decision => $_[0] }); print $J->encode($_[0]); exit 0 }
sub deny    { out({ hookSpecificOutput => { hookEventName => 'PreToolUse', permissionDecision => 'deny', permissionDecisionReason => "devteam: $_[0]" } }) }
sub context { out({ hookSpecificOutput => { hookEventName => $_[0], additionalContext => $_[1] } }) }

my %H = (
    guard => \&guard, 'state-protect' => \&state_protect, 'git-guard' => \&git_guard, route => \&route,
    'finish-gate' => \&finish_gate, 'turn-count' => \&turn_count, 'compact-reinject' => \&compact_reinject,
    ledger => \&ledger, trace => sub { },
);

sub dispatch {
    my ($name, $in) = @_;
    my $h = $H{$name} or die "devteam hook: unknown handler '$name'\n";
    my $st = state_read();
    return unless $st->{engaged};
    my $agent = length($in->{agent_id} // '') ? 1 : 0;
    my $owned = ($st->{owner_session} // '') eq ($in->{session_id} // '') ? 1 : 0;
    ($TRACE, $CUR) = (trace_on(), $name);
    trace({ event => $in->{hook_event_name}, agent => $agent, owned => $owned, status => $st->{status}, input => shrink($in) });
    # Main-thread events belong to the owning session only; subagent calls always belong to the engaged team.
    return if !$agent && !$owned;
    $st = tamper($st);
    $h->($in, $st, $agent);
    trace({ decision => 'none' });
}

# A protected file changed outside dt. During a goal that blocks the run; otherwise the edit is accepted.
sub tamper {
    my ($st) = @_;
    my $t = check_seal();
    return $st unless @$t;
    if ($st->{status} =~ /^(?:IDLE|ONBOARDING|STOPPED|BLOCKED)$/) { seal(); return $st }
    ledger_add({ event => 'tamper', files => $t });
    return update_state(sub {
        $_[0]{status} = 'BLOCKED';
        $_[0]{blocked_reason} = "protected files changed outside dt (@$t): review them, then run 'dt resync' and resume";
    });
}

sub guard {
    my ($in, $st, $agent) = @_;
    my $ti = $in->{tool_input} // {};
    my ($type, $iso) = ($ti->{subagent_type} // '', $ti->{isolation} // '');
    deny("agents may not start other agents (asked for '$type')") if $agent;
    locked(sub {
        my $s = state_read();
        my $stat = $s->{status};
        if ($stat eq 'IDLE') {
            deny('no goal is active; start one before using devteam agents') if $type =~ /^devteam:/;
            return;
        }
        if ($stat =~ /^(?:ACTIVE|VERIFYING)$/) {
            deny("only typed devteam:* agents may run during a goal (got '" . ($type || 'an untyped agent or fork') . "')")
              unless $type =~ /^devteam:/ || $type eq 'Explore';
            return unless $type =~ /^devteam:/;
            deny('only devteam:goal-verifier may run while the goal is VERIFYING') if $stat eq 'VERIFYING' && $type ne 'devteam:goal-verifier';
            deny("spawn cap reached ($s->{spawns}/$s->{spawn_cap} for the $s->{lane} lane); ask the user before spawning more") if $s->{spawns} >= $s->{spawn_cap};
            deny("worktree isolation needs the 'task_branches' git grant") if $iso eq 'worktree' && !$s->{git_grants}{task_branches};
            $s->{spawns}++;
            state_write($s);
            return;
        }
        return if $s->{adhoc} && $type =~ /^devteam:/;
        return if $stat eq 'ONBOARDING' && $type eq 'devteam:researcher';
        deny("no agents may start while the goal status is $stat (it must be confirmed and ACTIVE)");
    });
}

sub state_protect {
    my ($in, $st, $agent) = @_;
    return unless $agent;
    my $ti = $in->{tool_input} // {};
    my $f = $ti->{file_path} // $ti->{notebook_path} // return;
    $f = ($in->{cwd} // root()) . "/$f" unless $f =~ m{^/};
    $f =~ s{/+}{/}g;
    1 while $f =~ s{/\./}{/};
    1 while $f =~ s{/[^/]+/\.\./}{/};
    my $root = root();
    if ($f =~ m{^\Q$root\E/\.devteam/(.*)$}) {
        my $rel = $1;
        return if $rel =~ m{^(?:adr/|discussions/|knowledge/|goals/[^/]+/(?:design\.md|design-spec\.md|reference\.md|evidence/shots/|reports/))};
        deny("subagents may not write .devteam/$rel (state, criteria and the board belong to the PM and dt)");
    }
    (my $rel = $f) =~ s{^\Q$root\E/(?:\.claude/worktrees/[^/]+/)?}{} or return;
    my $g = goal_dir() or return;
    my $c = jread("$g/criteria.json") or return;
    deny("$rel is a locked acceptance test; only devteam:qa-engineer may change it")
      if exists $c->{locks}{$rel} && ($in->{agent_type} // '') ne 'devteam:qa-engineer';
}

sub git_guard {
    my ($in, $st, $agent) = @_;
    return unless $agent && ($in->{tool_name} // '') eq 'Bash';
    my $c = classify($in->{tool_input}{command} // '');
    my $tier = $c->{tier};
    return if $tier eq 'none' || $tier eq 'read';
    my $role = $in->{agent_type} // '';
    deny("this command could not be verified as safe git usage; use plain, separate git commands") if $tier eq 'unverifiable';
    deny("a '$tier' git/gh action needs the user's prompt every time; reply NEEDS_CONTEXT so the PM can ask") if $tier ne 'local';
    deny("role '$role' may not write to git") unless $WRITER{$role};
    deny("local git writes need the 'task_branches' grant the user approves in the combined confirmation") unless $st->{git_grants}{task_branches};
    deny('agents may not switch branches') if $c->{switch};
    my $branch = git_out($in->{cwd}, 'rev-parse', '--abbrev-ref', 'HEAD');
    deny("commits are allowed only on devteam/* or worktree-* branches (this is '$branch')") unless $branch =~ m{^(?:devteam/|worktree-)};
}

sub route {
    my ($in, $st, $agent) = @_;
    return if $agent || $st->{status} ne 'IDLE';
    my $p = $in->{prompt} // '';
    return if $p =~ m{^\s*/} || $p =~ /<(?:task-notification|cross-session-message|system-reminder)/;
    context('UserPromptSubmit', 'devteam is engaged and idle: treat this message as a new goal and run the devteam goal skill (intake), unless it is a plain question or a /devteam command.');
}

sub finish_gate {
    my ($in, $st, $agent) = @_;
    return unless $agent && $WRITER{ $in->{agent_type} // '' } && $st->{status} eq 'ACTIVE';
    my ($ok, $msg) = run_gates($in->{cwd} // root(), 0);
    return if $ok;
    my $cap = config_read()->{fix_rounds} // 3;
    my $n;
    update_state(sub {
        $n = ++$_[0]{retries}{ $in->{agent_id} };
        if ($n > $cap) {
            $_[0]{status} = 'BLOCKED';
            $_[0]{blocked_reason} = "gates still failing after $cap retries ($in->{agent_type})";
        }
    });
    if ($n > $cap) { ledger_add({ event => 'gate_exhausted', agent_type => $in->{agent_type} }); return }
    trace({ decision => { exit => 2, retry => $n } });
    print STDERR "devteam gate failed (retry $n of $cap). Fix it and finish again:\n$msg\n";
    exit 2;
}

sub turn_count {
    my ($in, $st, $agent) = @_;
    return if $agent;
    my $n;
    update_state(sub { $n = ++$_[0]{main_turns} if $_[0]{status} eq 'ACTIVE' });
    return unless $n && $st->{turn_cap} && $n == $st->{turn_cap};
    out({ systemMessage => "devteam: $n main-thread turns reached the $st->{lane} lane cap; consider upgrading the lane or asking the user." });
}

sub compact_reinject {
    my ($in, $st) = @_;
    return unless ($in->{source} // '') eq 'compact';
    my @l = ('devteam digest (you are the PM: use the devteam:orchestrate skill and `dt status`):',
        "status=$st->{status} goal=$st->{goal} lane=$st->{lane} lifecycle=$st->{lifecycle}",
        "spawns=$st->{spawns}/$st->{spawn_cap} grants=" . join(',', sort keys %{ $st->{git_grants} }));
    push @l, "blocked: $st->{blocked_reason}" if length $st->{blocked_reason};
    my $g = goal_dir();
    if ($g && open my $h, '<', "$g/board.md") {
        my @b = <$h>;
        push @l, 'board:', map { s/\s+\z//r } @b[0 .. ($#b < 11 ? $#b : 11)];
    }
    context('SessionStart', join("\n", @l));
}

sub ledger {
    my ($in, $st, $agent) = @_;
    my %r = (event => $agent ? 'subagent_stop' : 'main_stop', session => $in->{session_id},
        agent_type => $in->{agent_type}, agent_id => $in->{agent_id});
    delete $r{$_} for grep { !defined $r{$_} } keys %r;
    my $path = $agent ? $in->{agent_transcript_path} : $in->{transcript_path};
    if ($path) {
        my $of = ddir() . '/ledger.offset.' . ($agent ? "agent-$in->{agent_id}" : 'main');
        my ($t, $new) = usage_since($path, (slurp($of) // 0) + 0);
        $r{tokens} = $t if %$t;
        spit($of, $new);
    }
    ledger_add(\%r);
}

1;
