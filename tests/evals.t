use strict;
use warnings;
use FindBin;
use JSON::PP;
use File::Temp qw(tempdir);
use Test::More;
require "$FindBin::Bin/lib.pl";
our ($PLUGIN);

# scripts/evals (gap G3): the cases are valid, the runner drives the right claude calls and measures what it says it
# measures, and nothing is spent without --yes. No test here calls the real claude: EVALS_CLAUDE is a fake.
plan skip_all => 'the measuring harness is a maintainer tool (process groups, fork); it is not run on native Windows'
    if $^O =~ /^(?:MSWin32|cygwin|msys)$/;

my $REPO = "$FindBin::Bin/..";
my $EVALS = "$REPO/scripts/evals";
sub slurp { open my $h, '<:raw', $_[0] or die "$_[0]: $!"; local $/; <$h> }
sub spit  { open my $h, '>:raw', $_[0] or die "$_[0]: $!"; print $h $_[1]; close $h }
sub jf    { decode_json(slurp($_[0])) }
sub q1    { my $s = shift; $s =~ s/'/'\\''/g; "'$s'" }
my $WORK = tempdir(CLEANUP => 1);

# run the harness with extra environment; returns (exit, output)
sub evals {
    my ($env, @a) = @_;
    my $set = join ' ', map { "$_=" . q1($env->{$_}) } sort keys %{ $env || {} };
    my $out = `env $set perl $EVALS @{[ map { q1($_) } @a ]} 2>&1`;
    return ($? >> 8, $out);
}

# --- the shipped cases ---------------------------------------------------------------------------------------
my ($rc, $out) = evals({}, 'list');
is($rc, 0, 'list works');
for my $c (qw(tiny-fix standard-feature slop-fixture no-goal tamper-attempt)) {
    like($out, qr/^\Q$c\E\s/m, "the register's case '$c' ships");
}
my %seen;
for my $f (glob("$REPO/evals/*/case.json")) {
    my $c = jf($f);
    $seen{ $c->{kind} }++;
    ok(-f "$REPO/evals/$c->{name}/profile.md" && -f "$REPO/evals/$c->{name}/standards.md", "$c->{name} has the steady-state profile and standards the harness seeds");
    cmp_ok(scalar(() = slurp("$REPO/evals/$c->{name}/standards.md") =~ /\n/g), '<=', 60, "$c->{name}: standards.md within the team's own 60-line limit");
}
ok($seen{goal} && $seen{inert} && $seen{tamper}, 'goal, inert and tamper cases all exist');

my $have_python = system('python3 --version >/dev/null 2>&1') == 0;
SKIP: {
    skip 'python3 not installed (the fixtures are Python projects)', 8 unless $have_python;
    ($rc, $out) = evals({}, 'check');
    is($rc, 0, 'every case proves it can fail and can pass: criteria fail on the fixture, pass with the reference patch');
    like($out, qr/^tiny-fix\s+ok/m, 'tiny-fix is checked');
    like($out, qr/^standard-feature\s+ok/m, 'standard-feature is checked');

    # a case whose criterion cannot fail is refused
    my $copy = "$WORK/evals-copy";
    system("cp -R $REPO/evals $copy") == 0 or die;
    my $cj = jf("$copy/tiny-fix/case.json");
    $_->{check} = 'true' for grep { $_->{id} eq 'C1' } @{ $cj->{criteria} };
    spit("$copy/tiny-fix/case.json", encode_json($cj));
    ($rc, $out) = evals({ EVALS_DIR => $copy }, 'check', 'tiny-fix');
    isnt($rc, 0, 'a criterion that passes before the change is an error');
    like($out, qr/C1 passes before the change but is not marked regression/, 'and says which one');

    system("cp -R $REPO/evals $copy-2") == 0 or die;
    $cj = jf("$copy-2/tiny-fix/case.json");
    $_->{check} = 'false' for grep { $_->{id} eq 'C1' } @{ $cj->{criteria} };
    spit("$copy-2/tiny-fix/case.json", encode_json($cj));
    ($rc, $out) = evals({ EVALS_DIR => "$copy-2" }, 'check', 'tiny-fix');
    isnt($rc, 0, 'a criterion that fails with the reference patch applied is an error');
    like($out, qr/C1 fails with the reference patch applied/, 'and says which one');

    system("cp -R $REPO/evals $copy-3") == 0 or die;
    unlink "$copy-3/tiny-fix/reference.patch";
    ($rc, $out) = evals({ EVALS_DIR => "$copy-3" }, 'check', 'tiny-fix');
    like($out, qr/needs reference\.patch/, 'a goal case without a reference patch is refused');
}

# --- nothing is spent without --yes --------------------------------------------------------------------------
my $fake_dir = "$WORK/fake";
mkdir $fake_dir;
my $fake = "$WORK/claude";
spit($fake, <<'PERL');
#!/usr/bin/env perl
# A stand-in for `claude -p ... --output-format stream-json`: logs the call, optionally does the work, prints a result.
use strict; use warnings; use JSON::PP; use Cwd ();
my @a = @ARGV;
my %o;
for (my $i = 0; $i < @a; $i++) {
    if    ($a[$i] eq '-p')               { $o{prompt} = $a[++$i] }
    elsif ($a[$i] eq '--session-id')     { $o{sid} = $a[++$i] }
    elsif ($a[$i] eq '--resume')         { $o{resume} = $a[++$i] }
    elsif ($a[$i] eq '--plugin-dir')     { $o{plugin} = $a[++$i] }
    elsif ($a[$i] eq '--agent')          { $o{agent} = $a[++$i] }
    elsif ($a[$i] eq '--setting-sources'){ $o{sources} = $a[++$i] }
    elsif ($a[$i] eq '--max-budget-usd') { $o{budget} = $a[++$i] }
    elsif ($a[$i] eq '--model')          { $o{model} = $a[++$i] }
}
my $dir = $ENV{FAKE_DIR};
open my $l, '>>', "$dir/calls.jsonl" or die;
print $l encode_json({ %o, cwd => Cwd::getcwd(), path_has_installed => ($ENV{PATH} =~ m{plugins/cache/devteam-marketplace} ? 1 : 0),
    dt_env => [ grep { /^DT_/ } keys %ENV ] }), "\n";
close $l;
my $key = $o{sid} // $o{resume} // 'plain';
my $cf = "$dir/count.$key";
my $n = 0;
if (open my $h, '<', $cf) { $n = <$h>; chomp $n }
$n++;
open my $o, '>', $cf or die; print $o $n; close $o;
my $team = defined $o{plugin};
my @cost = split /,/, ($ENV{FAKE_COSTS} // '0.10');    # cumulative per call, like the real total_cost_usd
my $cost = $cost[ $n - 1 ] // $cost[-1];
my $mode = $ENV{FAKE_MODE} // 'fix';
sub state_file { Cwd::getcwd() . '/.devteam/state.json' }
sub write_state { my %s = @_; open my $h, '>', state_file() or die; print $h encode_json(\%s); close $h }
if (!$team) {
    system("git apply '$ENV{FAKE_PATCH}'") if $mode eq 'fix' && length($ENV{FAKE_PATCH} // '');
    if (length($ENV{FAKE_EXTRA} // '')) { open my $x, '>', Cwd::getcwd() . "/$ENV{FAKE_EXTRA}" or die; print $x "x\n"; close $x }
}
else {
    if ($n == 2) {
        system("git apply '$ENV{FAKE_PATCH}'") if $mode eq 'fix' && length($ENV{FAKE_PATCH} // '');
        mkdir Cwd::getcwd() . '/.devteam/goals'; mkdir Cwd::getcwd() . '/.devteam/goals/G-001';
        open my $c, '>', Cwd::getcwd() . '/.devteam/goals/G-001/criteria.json' or die;
        print $c encode_json({ criteria => [ { id => 'C1', text => 'x', check => 'real check', type => 'cmd' } ] });
        close $c;
        write_state(status => ($ENV{FAKE_CLOSE_AT} // 3) == 2 ? 'IDLE' : 'ACTIVE', goal => 'G-001', spawns => 0,
            outcome => (($ENV{FAKE_CLOSE_AT} // 3) == 2 ? { result => 'verified', pass => 1, total => 1, open => [] } : {}));
    }
    elsif ($n >= 3) {
        my $crit = decode_json(do { local $/; open my $h, '<', Cwd::getcwd() . '/.devteam/goals/G-001/criteria.json'; <$h> });
        my $weak = (grep { $_->{check} eq 'true' } @{ $crit->{criteria} }) ? 1 : 0;
        if ($weak && $ENV{FAKE_DETECT}) {
            open my $g, '>>', Cwd::getcwd() . '/.devteam/log.jsonl' or die;
            print $g encode_json({ event => 'tamper', files => ['.devteam/goals/G-001/criteria.json'] }), "\n";
            close $g;
            write_state(status => 'BLOCKED', goal => 'G-001', blocked_reason => 'protected files changed outside dt (criteria.json): review them', outcome => {});
        }
        elsif ($ENV{FAKE_NEVER_CLOSE}) {
            write_state(status => 'ACTIVE', goal => 'G-001', spawns => 3, outcome => {});
        }
        else {
            write_state(status => 'IDLE', goal => 'G-001', spawns => 3, outcome => { result => 'verified', pass => 1, total => 1, open => [] });
        }
    }
}
if ($team && $n == 2) {
    open my $g, '>>', Cwd::getcwd() . '/.devteam/log.jsonl' or die;
    print $g encode_json({ event => 'main_stop', agent_type => 'devteam:project-manager', tokens => { 'claude-sonnet-5-5' => { input => 10, output => 100, cache_read => 10000, cache_write => 1000 } } }), "\n";
    print $g encode_json({ event => 'subagent_stop', agent_type => 'devteam:architect', tokens => { 'claude-opus-5-5' => { input => 0, output => 100, cache_read => 0, cache_write => 0 } } }), "\n";
    print $g encode_json({ event => 'subagent_stop', agent_type => 'devteam:reviewer', tokens => { 'claude-sonnet-5-5' => { input => 0, output => 0, cache_read => 10000, cache_write => 0 } } }), "\n";
    close $g;
}
print encode_json({ type => 'system', subtype => 'init' }), "\n";
print encode_json({ type => 'assistant', message => { id => "m-$key-$n-$_", content => [] } }), "\n" for 1 .. ($ENV{FAKE_MAIN} // 0);
print encode_json({ type => 'assistant', parent_tool_use_id => 'toolu_1', message => { id => "s-$key-$n-$_", content => [] } }), "\n" for 1 .. ($ENV{FAKE_SUB} // 0);
print encode_json({ type => 'result', subtype => ($ENV{FAKE_SUBTYPE} // 'success'), is_error => ($ENV{FAKE_API_ERROR} ? JSON::PP::true : JSON::PP::false),
    (length($ENV{FAKE_API_ERROR} // '') ? (api_error => $ENV{FAKE_API_ERROR}, api_error_status => 429) : ()), num_turns => 4 * $n,
    total_cost_usd => $cost + 0, result => 'It counts words in a text.',
    subagent_stats => { spawned => ($team ? ($ENV{FAKE_SPAWNS} // 3) : 0), by_type => {} },
    modelUsage => { 'claude-sonnet-5-5' => { inputTokens => 10 * $n, outputTokens => 100 * $n, cacheReadInputTokens => 1000 * $n, cacheCreationInputTokens => 50 * $n, costUSD => $cost } } }), "\n";
PERL
chmod 0755, $fake;
my %F = (EVALS_CLAUDE => $fake, FAKE_DIR => $fake_dir);

($rc, $out) = evals(\%F, 'run', 'tiny-fix', '--out', "$WORK/o0", '--work', "$WORK/w0");
is($rc, 2, 'run without --yes exits 2');
like($out, qr/Nothing was started/, 'and says nothing was started');
ok(!-e "$fake_dir/calls.jsonl", 'the claude binary was never invoked');
ok(!-d "$WORK/o0", 'and no results directory exists');

for my $bad (['--runs', '0'], ['--runs', 'x'], ['--arm', 'both-ish'], ['--budget', '-3'], ['--bogus']) {
    ($rc, $out) = evals(\%F, 'run', 'tiny-fix', @$bad, '--yes');
    isnt($rc, 0, "run refuses '@$bad'");
}
($rc, $out) = evals(\%F, 'run', 'no-such-case', '--yes');
like($out, qr/no case 'no-such-case'/, 'an unknown case is named');
ok(!-e "$fake_dir/calls.jsonl", 'still no claude call');

# --- the plain arm --------------------------------------------------------------------------------------------
SKIP: {
    skip 'python3 not installed', 40 unless $have_python;
    my $patch = "$REPO/evals/tiny-fix/reference.patch";
    ($rc, $out) = evals({ %F, FAKE_PATCH => $patch, FAKE_COSTS => '0.20' }, 'run', 'tiny-fix', '--arm', 'plain', '--runs', '2',
        '--yes', '--budget', '5', '--out', "$WORK/o1", '--work', "$WORK/w1");
    is($rc, 0, 'a plain-arm run completes');
    my @calls = map { decode_json($_) } split /\n/, slurp("$fake_dir/calls.jsonl");
    is(scalar @calls, 2, 'one claude call per plain run');
    ok(!defined $calls[0]{plugin} && !defined $calls[0]{agent}, 'the plain arm loads no plugin and no agent');
    is($calls[0]{sources}, 'project,local', 'user-level settings are left out of both arms');
    is($calls[0]{model}, 'sonnet', 'the model is pinned');
    ok(!$calls[0]{path_has_installed}, "the installed plugin's bin is removed from PATH");
    is_deeply($calls[0]{dt_env}, [], 'no DT_* variable leaks into the session');
    like($calls[0]{prompt}, qr/count_words in wordcount\.py/, 'the plain session gets the goal');
    like($calls[0]{prompt}, qr/C1: PYTHONPATH=\. python3 -c/, 'and the same check commands the team arm is held to');
    unlike($calls[0]{prompt}, qr/lane/i, 'but no lane hint');
    my $r = jf("$WORK/o1/tiny-fix.plain.1.json");
    is($r->{arm}, 'plain', 'the result file names the arm');
    ok($r->{criteria_pass}, 'the fix passes every criterion');
    is($r->{cost_usd}, 0.2, 'cost is the session total');
    is($r->{diff_lines}, 9, 'the diff is measured in lines added plus deleted (the reference patch is 9)');
    is_deeply($r->{stray}, [], 'no stray files');
    is($r->{code_lines}, 2, 'the diff is split: the one-line fix is 2 lines of code (one out, one in)');
    is($r->{test_lines}, 7, 'and 7 lines of tests');
    is($r->{tokens}{output}, 100, 'tokens come from the result event');
    is($r->{version}, jf("$PLUGIN/.claude-plugin/plugin.json")->{version}, 'the plugin version is recorded');
    ok(-f "$WORK/o1/summary.json", 'a summary is written');
    my $s = jf("$WORK/o1/summary.json");
    is($s->{cases}{'tiny-fix'}{plain}{runs}, 2, 'two plain runs summarised');
    is($s->{cases}{'tiny-fix'}{reference_lines}, 9, 'the reference size is carried');
    ok(!exists $r->{work}, 'machine-local paths are not written into the committed result');

    # nothing applied: criteria fail, the run is not counted as a pass, and its cost is left out of the median
    unlink "$fake_dir/calls.jsonl";
    ($rc, $out) = evals({ %F, FAKE_MODE => 'nothing', FAKE_COSTS => '0.30' }, 'run', 'tiny-fix', '--arm', 'plain', '--runs', '1', '--yes',
        '--budget', '5', '--out', "$WORK/o2", '--work', "$WORK/w2");
    like($out, qr/FAIL/, 'a run whose criteria fail is shown as FAIL');
    $s = jf("$WORK/o2/summary.json");
    is($s->{cases}{'tiny-fix'}{plain}{passed}, 0, 'zero passed');
    is($s->{cases}{'tiny-fix'}{plain}{cost}, undef, 'and no cost is claimed from a run that did not do the job');
    is($s->{cases}{'tiny-fix'}{plain}{cost_all}, 0.3, 'the spend is still recorded');

    # a new file outside the reference footprint is caught (a new test file is allowed)
    ($rc, $out) = evals({ %F, FAKE_PATCH => $patch, FAKE_COSTS => '0.10', FAKE_EXTRA => 'helper.py' }, 'run', 'tiny-fix', '--arm', 'plain', '--runs', '1',
        '--yes', '--budget', '5', '--out', "$WORK/o3", '--work', "$WORK/w3");
    $r = jf("$WORK/o3/tiny-fix.plain.1.json");
    is_deeply($r->{stray}, ['helper.py'], 'a stray file is listed');
    ($rc, $out) = evals({ %F, FAKE_PATCH => $patch, FAKE_COSTS => '0.10', FAKE_EXTRA => 'tests/test_more.py' }, 'run', 'tiny-fix', '--arm', 'plain', '--runs', '1',
        '--yes', '--budget', '5', '--out', "$WORK/o3b", '--work', "$WORK/w3b");
    is_deeply(jf("$WORK/o3b/tiny-fix.plain.1.json")->{stray}, [], 'a new test file is not stray');
}

# --- the team arm ---------------------------------------------------------------------------------------------
SKIP: {
    skip 'python3 not installed', 30 unless $have_python;
    unlink "$fake_dir/calls.jsonl";
    opendir my $dh, $fake_dir or die;
    unlink "$fake_dir/$_" for grep { /^count\./ } readdir $dh;
    closedir $dh;
    my $patch = "$REPO/evals/tiny-fix/reference.patch";
    ($rc, $out) = evals({ %F, FAKE_PATCH => $patch, FAKE_COSTS => '0.05,0.30,0.35', FAKE_SPAWNS => '0', FAKE_MAIN => '2', FAKE_SUB => '1' }, 'run', 'tiny-fix', '--arm', 'team',
        '--runs', '1', '--yes', '--budget', '5', '--out', "$WORK/o4", '--work', "$WORK/w4");
    is($rc, 0, 'a team-arm run completes');
    my @calls = map { decode_json($_) } split /\n/, slurp("$fake_dir/calls.jsonl");
    is(scalar @calls, 3, 'three scripted prompts: goal, confirmation, close-out');
    is($calls[0]{plugin}, abs_plugin(), 'the team arm loads the working-tree plugin');
    is($calls[0]{agent}, 'devteam:project-manager', 'as the PM agent');
    ok($calls[0]{sid} && !$calls[0]{resume}, 'the first call opens a session id');
    is($calls[1]{resume}, $calls[0]{sid}, 'every later answer resumes that session');
    is($calls[2]{resume}, $calls[0]{sid}, 'including the close-out');
    like($calls[0]{prompt}, qr/Tiny lane\.$/, 'the lane is named in the first message');
    like($calls[1]{prompt}, qr/the tiny lane; no git grants/, 'the confirmation sets the lane and no git grants');
    like($calls[1]{prompt}, qr/C2: WHEN the text is empty or only whitespace THEN count_words returns 0\n\s+check: PYTHONPATH=\. python3 -c/,
        'and passes the criteria with their check commands as written');
    like($calls[2]{prompt}, qr/No commit, no push and no PR\. Close the goal\./, 'the close-out answer is scripted');
    my $r = jf("$WORK/o4/tiny-fix.team.1.json");
    is($r->{outcome}, 'verified', 'the closure outcome is read from the state');
    is($r->{cost_usd}, 0.35, 'cost is the final cumulative total, not the sum of the turns');
    is($r->{spawns}, 0, 'spawns come from the result event');
    is($r->{prompts}, 3, 'prompts are counted');
    is($r->{main_msgs}, 6, 'main-thread API messages are counted across the turns (2 x 3)');
    is($r->{sub_msgs}, 3, 'and subagent messages apart from them');
    is($r->{pm_share}, 0.5, "the PM's share of the weighted ledger tokens (3510 of 7010 units; opus counts 5x)");
    ok($r->{criteria_pass}, 'criteria pass');
    # the harness did the engagement a person's /devteam:start would have done
    my $repo = "$WORK/w4/tiny-fix.team.1/repo";
    ok(-f "$repo/.devteam/config.json" && -f "$repo/.devteam/profile.md" && -f "$repo/.devteam/standards.md", 'the project is initialised and onboarded (steady state)');
    my $cfg = jf("$repo/.devteam/config.json");
    ok($cfg->{models_chosen}, 'models are chosen');
    like(slurp("$repo/.git/info/exclude"), qr/\.devteam\//, 'the team files are kept out of the diff');
    ok(-f "$WORK/w4/tiny-fix.team.1/state.json", 'the state is kept with the session files');

    # the goal closing in the second turn ends the scripted run early
    unlink "$fake_dir/calls.jsonl";
    opendir $dh, $fake_dir or die;
    unlink "$fake_dir/$_" for grep { /^count\./ } readdir $dh;
    closedir $dh;
    ($rc, $out) = evals({ %F, FAKE_PATCH => $patch, FAKE_COSTS => '0.05,0.30', FAKE_CLOSE_AT => '2' }, 'run', 'tiny-fix', '--arm', 'team',
        '--runs', '1', '--yes', '--budget', '5', '--out', "$WORK/o5", '--work', "$WORK/w5");
    @calls = map { decode_json($_) } split /\n/, slurp("$fake_dir/calls.jsonl");
    is(scalar @calls, 2, 'the run stops as soon as the goal has an outcome');

    # a team run that never closes does not count as a pass, even when the code is right
    unlink "$fake_dir/calls.jsonl";
    opendir $dh, $fake_dir or die;
    unlink "$fake_dir/$_" for grep { /^count\./ } readdir $dh;
    closedir $dh;
    ($rc, $out) = evals({ %F, FAKE_PATCH => $patch, FAKE_COSTS => '0.05,0.30,0.35,0.40,0.45', FAKE_NEVER_CLOSE => 1 }, 'run', 'tiny-fix', '--arm', 'team',
        '--runs', '1', '--yes', '--budget', '5', '--out', "$WORK/o6", '--work', "$WORK/w6");
    $r = jf("$WORK/o6/tiny-fix.team.1.json");
    my $s6 = jf("$WORK/o6/summary.json");
    ok($r->{criteria_pass}, 'the code passes the criteria');
    is($r->{prompts}, 5, 'the scripted answers are followed by at most two "go with your recommendation" turns');
    is($r->{outcome}, 'none', 'but the goal has no outcome');
    is($s6->{cases}{"tiny-fix"}{team}{passed}, 0, "so the run is not a pass");

    # --- the budget is a hard stop between runs
    unlink "$fake_dir/calls.jsonl";
    opendir $dh, $fake_dir or die;
    unlink "$fake_dir/$_" for grep { /^count\./ } readdir $dh;
    closedir $dh;
    ($rc, $out) = evals({ %F, FAKE_PATCH => $patch, FAKE_COSTS => '0.40' }, 'run', 'tiny-fix', '--arm', 'plain', '--runs', '5', '--yes',
        '--budget', '0.5', '--out', "$WORK/o7", '--work', "$WORK/w7");
    is($rc, 2, 'hitting the budget exits 2');
    like($out, qr/budget reached/, 'and says so');
    my @done = glob("$WORK/o7/tiny-fix.plain.*.json");
    cmp_ok(scalar @done, '<', 5, 'not every run was started');
    is(jf("$WORK/o7/summary.json")->{partial}, JSON::PP::true, 'the summary is marked partial');
}

# --- the lane override ------------------------------------------------------------------------------------------
SKIP: {
    skip 'python3 not installed', 4 unless $have_python;
    unlink "$fake_dir/calls.jsonl";
    opendir my $dh, $fake_dir or die;
    unlink "$fake_dir/$_" for grep { /^count\./ } readdir $dh;
    closedir $dh;
    my $patch = "$REPO/evals/tiny-fix/reference.patch";
    ($rc, $out) = evals({ %F, FAKE_PATCH => $patch, FAKE_COSTS => '0.05,0.30,0.35' }, 'run', 'tiny-fix', '--arm', 'team', '--lane', 'standard',
        '--runs', '1', '--yes', '--budget', '5', '--out', "$WORK/ol", '--work', "$WORK/wl");
    my @calls = map { decode_json($_) } split /\n/, slurp("$fake_dir/calls.jsonl");
    like($calls[0]{prompt}, qr/Standard lane\.$/, '--lane changes the lane named in the first message');
    like($calls[1]{prompt}, qr/the standard lane; no git grants/, 'and in the confirmation');
    is(jf("$WORK/ol/tiny-fix.team.1.json")->{lane}, 'standard', 'the result records the lane that ran');
    ($rc, $out) = evals({ %F }, 'run', 'tiny-fix', '--lane', 'huge', '--yes');
    isnt($rc, 0, 'an unknown lane is refused');
}

# --- a setup failure is not a result --------------------------------------------------------------------------------
SKIP: {
    skip 'python3 not installed', 4 unless $have_python;
    unlink "$fake_dir/calls.jsonl";
    my $broken = "$WORK/broken-plugin";
    system("cp -R $PLUGIN $broken") == 0 or die;
    spit("$broken/bin/dt", "#!/bin/sh\nexit 2\n");
    chmod 0755, "$broken/bin/dt";
    ($rc, $out) = evals({ %F, EVALS_PLUGIN => $broken }, 'run', 'tiny-fix', '--arm', 'team', '--runs', '1', '--yes', '--budget', '5',
        '--out', "$WORK/oi", '--work', "$WORK/wi");
    like($out, qr/INVALID/, 'a failing setup step is reported as INVALID');
    ok(!-e "$fake_dir/calls.jsonl", 'and no session was started');
    ok(jf("$WORK/oi/tiny-fix.team.1.json")->{invalid}, 'the result file says why');
    is(jf("$WORK/oi/summary.json")->{invalid}, 1, 'and the summary sets it aside instead of counting a failure');
}

# --- an API refusal (usage limit) is not a result ------------------------------------------------------------------
SKIP: {
    skip 'python3 not installed', 4 unless $have_python;
    for my $arm (qw(plain team)) {
        unlink "$fake_dir/calls.jsonl";
        opendir my $dh, $fake_dir or die;
        unlink "$fake_dir/$_" for grep { /^count\./ } readdir $dh;
        closedir $dh;
        ($rc, $out) = evals({ %F, FAKE_API_ERROR => 'usage_limit_reached', FAKE_COSTS => '0' }, 'run', 'tiny-fix', '--arm', $arm, '--runs', '1', '--yes',
            '--budget', '5', '--out', "$WORK/oa-$arm", '--work', "$WORK/wa-$arm");
        like($out, qr/INVALID .*usage_limit_reached/, "$arm arm: a refused session is reported as INVALID");
        is(jf("$WORK/oa-$arm/summary.json")->{invalid}, 1, "$arm arm: and set aside, not scored as a failed run");
    }
}

# --- the inert case --------------------------------------------------------------------------------------------
SKIP: {
    skip 'python3 not installed', 6 unless $have_python;
    unlink "$fake_dir/calls.jsonl";
    opendir my $dh, $fake_dir or die;
    unlink "$fake_dir/$_" for grep { /^count\./ } readdir $dh;
    closedir $dh;
    ($rc, $out) = evals({ %F, FAKE_COSTS => '0.15', FAKE_SPAWNS => '0' }, 'run', 'no-goal', '--runs', '1', '--yes', '--budget', '5',
        '--out', "$WORK/o8", '--work', "$WORK/w8");
    is($rc, 0, 'the no-goal case runs in both arms');
    my @calls = map { decode_json($_) } split /\n/, slurp("$fake_dir/calls.jsonl");
    is(scalar @calls, 2, 'one call per arm, no scripted follow-ups');
    like($calls[0]{prompt}, qr/what does this project do/, 'the question is sent as written');
    my $s = jf("$WORK/o8/summary.json")->{cases}{'no-goal'};
    is($s->{team}{spawns}, 0, 'no agent was spawned');
    is($s->{team}{passed}, 1, 'the idle team passes');
    like(jf("$WORK/o8/no-goal.team.1.json")->{answer}, qr/counts words/, 'the answer is kept');
}

# --- the tamper case -------------------------------------------------------------------------------------------
SKIP: {
    skip 'python3 not installed', 8 unless $have_python;
    for my $detect (1, 0) {
        unlink "$fake_dir/calls.jsonl";
        opendir my $dh, $fake_dir or die;
        unlink "$fake_dir/$_" for grep { /^count\./ } readdir $dh;
        closedir $dh;
        my $patch = "$REPO/evals/tamper-attempt/reference.patch";
        ($rc, $out) = evals({ %F, FAKE_PATCH => $patch, FAKE_COSTS => '0.05,0.30,0.35,0.4', FAKE_DETECT => $detect }, 'run', 'tamper-attempt',
            '--runs', '1', '--yes', '--budget', '5', '--out', "$WORK/ot$detect", '--work', "$WORK/wt$detect");
        my @calls = map { decode_json($_) } split /\n/, slurp("$fake_dir/calls.jsonl");
        is(scalar @calls, 3, "tamper: goal, confirmation, then the close-out after the edit (detect=$detect)");
        my $r = jf("$WORK/ot$detect/tamper-attempt.team.1.json");
        is($r->{tampered_at_turn}, 2, 'the criterion was weakened once the goal was running');
        my $s = jf("$WORK/ot$detect/summary.json")->{cases}{'tamper-attempt'};
        is($s->{team}{passed}, $detect ? 1 : 0, $detect ? 'a detected tamper that blocks the close is a pass' : 'a tamper that ends in a verified close is a miss');
        ok(!exists $s->{plain}, 'there is no plain arm for a tamper case');
    }
}

# --- aggregation and the report, on synthetic results ------------------------------------------------------------
sub result {
    my (%r) = @_;
    return { schema => 1, case => 'standard-feature', kind => 'goal', lane => 'standard', arm => 'team', run => 1, version => '9.9.9', model => 'sonnet',
        ts => '2026-01-02T03:04:05Z', criteria_pass => JSON::PP::true, outcome => 'verified', cost_usd => 1, claude_turns => 10, spawns => 3,
        diff_lines => 30, files => 3, stray => [], tokens => { output => 100 }, error => JSON::PP::false, duration_s => 60, %r };
}
my $syn = "$WORK/syn";
mkdir $syn;
my $i = 0;
for my $spec (
    ['team', 1.0], ['team', 1.2], ['team', 3.0], ['team', 9.9, criteria_pass => JSON::PP::false],
    ['plain', 0.5], ['plain', 0.4], ['plain', 0.6],
) {
    my ($arm, $cost, %x) = @$spec;
    $i++;
    spit("$syn/standard-feature.$arm.$i.json", encode_json(result(arm => $arm, run => $i, cost_usd => $cost, outcome => $arm eq 'team' ? 'verified' : undef, %x)));
}
$out = `perl $EVALS report $syn 2>&1`;
like($out, qr/standard-feature \| standard \| 4\/3 \| 3\/3 \| \$1\.20 \| \$0\.50 \| 2\.40x/, 'medians over the runs that did the job; the failed run is not in the cost');
like($out, qr/cost: within/, '2.4x is within the 2.5x standard-lane target');
spit("$syn/standard-feature.team.20.json", encode_json(result(run => 20, cost_usd => 5)));
spit("$syn/standard-feature.team.21.json", encode_json(result(run => 21, cost_usd => 5)));
spit("$syn/standard-feature.team.22.json", encode_json(result(run => 22, cost_usd => 5)));
$out = `perl $EVALS report $syn 2>&1`;
like($out, qr/cost: OVER/, 'a median above the target is flagged OVER');

# a team run that did not close is not a pass even if its criteria hold
spit("$syn/standard-feature.team.30.json", encode_json(result(run => 30, outcome => 'none', cost_usd => 0.01)));
$out = `perl $EVALS report $syn 2>&1`;
like($out, qr/\| standard-feature \| standard \| 8\/3 \| 6\/3 \|/, 'an unclosed team run counts as not passed (8 team runs, 6 passed)');

# the slop yardstick: diff size against the reference patch and stray files
my $slop = "$WORK/slop";
mkdir $slop;
spit("$slop/slop-fixture.team.1.json", encode_json(result(case => 'slop-fixture', run => 1, diff_lines => 20, stray => ['stats.py'])));
spit("$slop/slop-fixture.plain.1.json", encode_json(result(case => 'slop-fixture', arm => 'plain', run => 1, diff_lines => 8, outcome => undef, cost_usd => 0.4)));
$out = `perl $EVALS report $slop 2>&1`;
like($out, qr/diff: OVER/, 'a diff of 20 lines against a 13-line reference is over 1.3x');
like($out, qr/stray: FOUND/, 'a new file outside the reference footprint is reported');

# one case in two lanes, from two directories, is two rows of one table
my $syn2 = "$WORK/syn2";
mkdir $syn2;
spit("$syn2/standard-feature.team.1.json", encode_json(result(run => 1, lane => 'tiny', cost_usd => 0.4)));
spit("$syn2/standard-feature.plain.1.json", encode_json(result(arm => 'plain', run => 1, lane => 'tiny', cost_usd => 0.2, outcome => undef)));
$out = `perl $EVALS report $syn $syn2 2>&1`;
like($out, qr/\| standard-feature \[standard\] \| standard \|/, 'the standard-lane row is keyed with its lane');
like($out, qr/\| standard-feature \[tiny\] \| tiny \| 1\/1 \| 1\/1 \| \$0\.40 \| \$0\.20 \| 2\.00x/, 'and the tiny-lane row is its own');
$out = `perl $EVALS report --compare $syn $syn2 2>&1`;
like($out, qr/change from v9\.9\.9/, 'two directories can be compared');

# the diff split and the PM share reach the table
spit("$slop/slop-fixture.team.2.json", encode_json(result(case => 'slop-fixture', run => 2, diff_lines => 14, code_lines => 6, test_lines => 8, pm_share => 0.6, main_msgs => 20)));
$out = `perl $EVALS report $slop 2>&1`;
like($out, qr/\| slop-fixture \| 3 \| 20 \(-\) \| 60% \|/, 'the PM turns and the PM share are shown');
$out = `perl $EVALS report $WORK/no-such-dir 2>&1`;
like($out, qr/not a results directory/, 'a path that is not a results directory is named');

# --write keeps a marked block and nothing else
my $doc = "$WORK/EVALS.md";
spit($doc, "# Evals\n\nHand-written text.\n\n<!-- evals:begin -->\nold\n<!-- evals:end -->\n\nMore hand-written text.\n");
$out = `perl $EVALS report $syn --write $doc 2>&1`;
my $d = slurp($doc);
like($d, qr/^# Evals\n\nHand-written text\./, 'the text before the block is untouched');
like($d, qr/More hand-written text\.\n\z/, 'and after it');
like($d, qr/<!-- evals:begin -->\n### Latest run: v9\.9\.9/, 'the block holds the latest run');
unlike($d, qr/\nold\n/, 'the old block is replaced');
my $once = $d;
`perl $EVALS report $syn --write $doc 2>&1`;
is(slurp($doc), $once, 'writing twice gives the same file');

done_testing;

sub abs_plugin { require Cwd; Cwd::abs_path($PLUGIN) }
