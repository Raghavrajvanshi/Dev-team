package DT;
# Core helpers shared by the dt CLI and the hooks: paths, JSON, state, config, seal, command runner.
use strict;
use warnings;
use JSON::PP;
use Digest::SHA;
use File::Path qw(make_path);
use File::Basename qw(dirname);
use Cwd qw(getcwd abs_path);
use POSIX qw(strftime setsid);
use Fcntl qw(:flock);
use Exporter 'import';
our @EXPORT_OK = qw(root ddir slurp spit jread jwrite ts true false
  default_state default_config state_read state_write config_read config_write
  goal_dir protected_files seal check_seal sha_file git_out tree_key run_cmd ledger_add
  locked update_state run_gates usage_since);

my $JSON = JSON::PP->new->canonical->pretty->utf8;
sub true  { JSON::PP::true }
sub false { JSON::PP::false }
sub ts    { strftime('%Y-%m-%dT%H:%M:%SZ', gmtime) }

sub root {
    return $ENV{DT_ROOT} if $ENV{DT_ROOT};
    return $ENV{CLAUDE_PROJECT_DIR} if $ENV{CLAUDE_PROJECT_DIR} && -d "$ENV{CLAUDE_PROJECT_DIR}/.devteam";
    my $d = getcwd();
    while (1) {
        return $d if -d "$d/.devteam";
        my $p = dirname($d);
        last if $p eq $d;
        $d = $p;
    }
    my $common = git_out(undef, 'rev-parse', '--git-common-dir');
    if (length $common) {
        $common = abs_path($common) // $common;
        return dirname($common) if $common =~ m{/\.git$};
    }
    return $ENV{CLAUDE_PROJECT_DIR} || getcwd();
}
sub ddir { root() . '/.devteam' }

sub slurp { my ($f) = @_; open my $h, '<:raw', $f or return undef; local $/; my $c = <$h>; close $h; $c }
sub spit {
    my ($f, $c) = @_;
    make_path(dirname($f));
    open my $h, '>:raw', "$f.tmp.$$" or die "cannot write $f: $!\n";
    print $h $c;
    close $h;
    rename "$f.tmp.$$", $f or die "cannot rename $f: $!\n";
}
sub jread  { my $c = slurp($_[0]); defined $c ? decode_json($c) : undef }
sub jwrite { spit($_[0], $JSON->encode($_[1])) }

sub default_state {
    return {
        engaged => false, owner_session => '', status => 'IDLE', goal => '', lane => '',
        lifecycle => '', original_branch => '', original_sha => '', integration_branch => '',
        adhoc => false, spawns => 0, spawn_cap => 0, main_turns => 0, turn_cap => 0, returns => 0,
        retries => {}, git_grants => {}, queue => [], blocked_reason => '', ledger_offset => 0, updated => '',
        outcome => {},    # how the last goal ended: { result: verified|partial|failed|blocked, why, pass, total, open, ts }
    };
}

sub default_config {
    my %m = (
        architect => ['opus', 'high'], 'security-engineer' => ['sonnet', 'high'],
        'fullstack-engineer' => ['sonnet', 'high'], 'backend-engineer' => ['sonnet', 'medium'],
        'frontend-engineer' => ['sonnet', 'medium'], 'mobile-engineer' => ['sonnet', 'medium'],
        'devops-engineer' => ['sonnet', 'medium'], 'qa-engineer' => ['sonnet', 'medium'],
        reviewer => ['sonnet', 'high'], 'goal-verifier' => ['sonnet', 'medium'],
        researcher => ['sonnet', 'medium'], 'tech-writer' => ['haiku', 'low'], 'ux-designer' => ['sonnet', 'high'],
    );
    return {
        version => 1, trace => false,
        models => { map { $_ => { model => $m{$_}[0], effort => $m{$_}[1] } } keys %m },
        escalation => 'opus', models_chosen => false,
        lanes => {
            tiny     => { spawn_cap => 0,  turn_cap => 15 },
            standard => { spawn_cap => 7,  turn_cap => 0 },
            large    => { spawn_cap => 20, turn_cap => 0 },
        },
        gates => { format => '', typecheck => '', test_affected => '', test => '', install => '', timeout => 300 },
        git => { localWrites => 'per-goal' },
        lifecycle => { phaseStops => false },
        soft => { function_lines => 40, file_lines => 300, params => 4 },
        prices => { opus => 5, sonnet => 1, haiku => 0.25 },
        fix_rounds => 3,
        sessions => { live_secs => 1800 },    # a session active within this many seconds counts as live
    };
}

sub state_read  { jread(ddir() . '/state.json') // default_state() }
sub config_read { jread(ddir() . '/config.json') // default_config() }
# Reentrant exclusive lock: hooks run in parallel and must not lose each other's state updates.
my ($LFH, $LDEPTH) = (undef, 0);
sub locked {
    my ($cb) = @_;
    if (!$LDEPTH) { make_path(ddir()); open $LFH, '>>', ddir() . '/lock' or die "lock: $!\n"; flock($LFH, LOCK_EX) }
    $LDEPTH++;
    my @r = eval { $cb->() };
    my $e = $@;
    if (!--$LDEPTH) { flock($LFH, LOCK_UN); close $LFH }
    die $e if $e;
    return wantarray ? @r : $r[0];
}
sub state_write  { my ($s) = @_; locked(sub { $s->{updated} = ts(); jwrite(ddir() . '/state.json', $s); seal() }) }
sub config_write { my ($c) = @_; locked(sub { jwrite(ddir() . '/config.json', $c); seal() }) }
sub update_state { my ($cb) = @_; locked(sub { my $s = state_read(); $cb->($s); state_write($s); $s }) }

sub goal_dir {
    my $g = shift // state_read()->{goal};
    return length($g // '') ? ddir() . "/goals/$g" : undef;
}

# Files whose content only dt may change. A mismatch means a hand edit or tampering.
sub protected_files {
    my @f = (ddir() . '/state.json', ddir() . '/config.json');
    my $g = goal_dir();
    push @f, "$g/criteria.json" if $g;
    return grep { -f $_ } @f;
}
sub sha_file {
    my ($f) = @_;
    open my $h, '<:raw', $f or return '';
    my $d = Digest::SHA->new(256)->addfile($h)->hexdigest;
    close $h;
    return $d;
}
sub seal {
    locked(sub {
        my $root = root();
        my %s = map { (substr($_, length($root) + 1) => sha_file($_)) } protected_files();
        jwrite(ddir() . '/seal.json', \%s);
    });
}
sub check_seal {
    my $s = jread(ddir() . '/seal.json') or return [];
    my $root = root();
    return [ grep { ($s->{$_} // '') ne sha_file("$root/$_") } map { substr($_, length($root) + 1) } protected_files() ];
}

# git helper: list-form exec, no shell. Returns trimmed stdout ('' on failure).
sub git_out {
    my ($cwd, @args) = @_;
    my $pid = open(my $h, '-|') // return '';
    if (!$pid) {
        chdir $cwd if defined $cwd;
        open STDERR, '>', '/dev/null';
        exec 'git', @args or exit 127;
    }
    local $/;
    my $out = <$h> // '';
    close $h;
    $out =~ s/\s+\z//;
    return $out;
}

# Content key of the working tree: HEAD tree + uncommitted diff + untracked files, ignoring .devteam.
sub tree_key {
    my ($cwd) = @_;
    my $c = Digest::SHA->new(256);
    $c->add(git_out($cwd, 'rev-parse', 'HEAD^{tree}'), "\0", git_out($cwd, 'diff', 'HEAD', '--', '.', ':!.devteam', ':!.claude/settings.local.json'));
    my $untracked = git_out($cwd, 'ls-files', '-o', '--exclude-standard', '-z', '--', '.', ':!.devteam', ':!.claude/settings.local.json');
    for my $f (sort split /\0/, $untracked) {
        $c->add("\0$f\0");
        if (open my $h, '<:raw', "$cwd/$f") { $c->addfile($h); close $h }
    }
    return $c->hexdigest;
}

# Run a shell command with a timeout in its own process group. Returns ($exit, $tail, $timed_out).
sub run_cmd {
    my ($cmd, $cwd, $timeout) = @_;
    $timeout ||= 300;
    my $tmp = "/tmp/dt-run-$$-" . int(rand(1e9));
    my $pid = fork() // die "fork: $!\n";
    if (!$pid) {
        setsid();
        chdir $cwd if defined $cwd;
        open STDIN, '<', '/dev/null';
        open STDOUT, '>', $tmp;
        open STDERR, '>&', \*STDOUT;
        exec 'sh', '-c', $cmd or exit 127;
    }
    my $timed_out = 0;
    eval {
        local $SIG{ALRM} = sub { $timed_out = 1; kill 'TERM', -$pid; die "timeout\n" };
        alarm $timeout;
        waitpid($pid, 0);
        alarm 0;
    };
    if ($timed_out) { sleep 1; kill 'KILL', -$pid; waitpid($pid, 0) }
    my $exit = $timed_out ? 124 : ($? >> 8);
    my @lines = split /\n/, (slurp($tmp) // '');
    unlink $tmp;
    @lines = @lines[-40 .. -1] if @lines > 40;
    return ($exit, join("\n", @lines), $timed_out);
}

sub ledger_add {
    my ($rec) = @_;
    $rec->{ts} //= ts();
    my $f = ddir() . '/log.jsonl';
    make_path(dirname($f));
    open my $h, '>>', $f or return;
    print $h JSON::PP->new->canonical->encode($rec), "\n";
    close $h;
}

# Run the configured gates in $cwd. Results are cached by tree hash, so an identical tree is never tested twice.
sub run_gates {
    my ($cwd, $full) = @_;
    my $g = config_read()->{gates};
    my @plan = (['format', $g->{format}], ['typecheck', $g->{typecheck}],
        $full ? ['test', $g->{test}] : ['test_affected', $g->{test_affected} || $g->{test}]);
    my $key = tree_key($cwd);
    my $gd = goal_dir();
    my $dir = $gd ? "$gd/evidence" : ddir() . '/evidence';
    my ($ran, $notes) = (0, '');
    for my $step (@plan) {
        my ($name, $line) = @$step;
        next unless length($line // '');
        $ran++;
        my $ev = "$dir/gate-$name-$key.json";
        if (-f $ev) { $notes .= "cached $name; "; next }
        my ($ex, $tail, $to) = run_cmd($line, $cwd, $g->{timeout} || 300);
        return (0, "gate '$name' " . ($to ? 'timed out' : "failed (exit $ex)") . ": $line\n$tail") if $ex != 0;
        jwrite($ev, { gate => $name, tree => $key, exit => 0, ts => ts() });
        $notes .= "ran $name; ";
    }
    return (1, $ran ? $notes : 'gates not configured');
}

# Token usage appended to a transcript since byte offset $off. Best effort: tolerates unknown line shapes.
sub usage_since {
    my ($path, $off) = @_;
    $off //= 0;
    return ({}, $off) unless defined $path && -f $path;
    open my $h, '<:raw', $path or return ({}, $off);
    $off = 0 if $off > -s $path;
    seek $h, $off, 0;
    my %t;
    while (my $l = <$h>) {
        last unless $l =~ /\n\z/;
        $off += length $l;
        next unless $l =~ /"usage"/;
        my $u = eval { decode_json($l)->{message} } or next;
        my $use = $u->{usage} or next;
        my $m = $u->{model} // 'unknown';
        $t{$m}{input} += $use->{input_tokens} // 0;
        $t{$m}{output} += $use->{output_tokens} // 0;
        $t{$m}{cache_read} += $use->{cache_read_input_tokens} // 0;
        $t{$m}{cache_write} += $use->{cache_creation_input_tokens} // 0;
    }
    return (\%t, $off);
}

1;
