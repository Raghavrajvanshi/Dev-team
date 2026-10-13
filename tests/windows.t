use strict;
use warnings;
use FindBin;
use JSON::PP;
use File::Temp qw(tempdir);
use Test::More;
require "$FindBin::Bin/lib.pl";
use lib "$FindBin::Bin/../plugins/devteam/lib";
use Cwd ();
use DT qw(native_path win_path lock_ok sha_file);
use DT::Sessions ();
our ($PLUGIN, $REPO);

# Native Windows with Git for Windows (gap G14): the spellings of a path, line endings that move under a lock,
# and what runs without a POSIX tool chain. The platform-specific parts run on every OS by naming the platform.
sub slurp { open my $h, '<:raw', $_[0] or die "$_[0]: $!"; local $/; <$h> }
sub decision { my $j = eval { decode_json($_[0]) } or return ''; $j->{hookSpecificOutput}{permissionDecision} // '' }

# --- one spelling per path ---
my @msys = (
    ['C:\\Users\\me\\proj\\x.py', '/c/Users/me/proj/x.py', 'a Windows path with backslashes'],
    ['c:/Users/me/proj',          '/c/Users/me/proj',      'a Windows path with slashes and a lower-case drive'],
    ['D:\\',                      '/d/',                   'a drive root'],
    ['D:',                        '/d',                    'a bare drive'],
    ['/c/Users/me',               '/c/Users/me',           'an MSYS path stays'],
    ['/cygdrive/c/Users/me',      '/c/Users/me',           'a Cygwin path becomes an MSYS one'],
    ['\\\\srv\\share\\x',         '//srv/share/x',         'a UNC path'],
    ['src\\a.py',                 'src/a.py',              'a relative path'],
    ['/home/me/x',                '/home/me/x',            'a plain POSIX path stays'],
    ['/c',                        '/c',                    'a one-letter top folder is a drive in MSYS'],
);
is(native_path($_->[0], 'msys'), $_->[1], "msys: $_->[2]") for @msys;
is(native_path('C:\\Users\\me', 'cygwin'), '/cygdrive/c/Users/me', 'cygwin: a drive path');
is(native_path('/cygdrive/d/x', 'cygwin'), '/cygdrive/d/x', 'cygwin: its own spelling stays');
is(native_path('/c/Users/me', 'MSWin32'), 'C:/Users/me', 'native perl: an MSYS path becomes a drive path');
is(native_path('C:\\Users\\me\\x', 'MSWin32'), 'C:/Users/me/x', 'native perl: backslashes become slashes');
is(native_path('c:\\x', 'MSWin32'), 'C:/x', 'native perl: the drive is upper-case');
is(native_path('C:\\Users\\me\\x', 'linux'), 'C:\\Users\\me\\x', 'linux: nothing is touched (a backslash is a name character there)');
is(native_path('C:\\Users\\me\\x', 'darwin'), 'C:\\Users\\me\\x', 'macOS: nothing is touched');
is(native_path(undef, 'msys'), undef, 'undef stays undef');
is(native_path('', 'msys'), '', 'and so does an empty path');
is(win_path('/c/Users/me/proj'), 'C:\\Users\\me\\proj', 'the Windows spelling of an MSYS path');
is(win_path('/cygdrive/d/x'), 'D:\\x', '... of a Cygwin path');
is(win_path('/home/me'), '/home/me', '... and a path with no drive is left alone');

# --- a lock survives a line-ending change, and only that ---
my $dir = tempdir(CLEANUP => 1);
my $f = "$dir/t.txt";
sub put { open my $h, '>:raw', $f or die; print $h $_[0]; close $h }
put("one\ntwo\n");
my $lock = sha_file($f);
ok(lock_ok($f, $lock), 'a file that has not changed holds');
put("one\r\ntwo\r\n");
ok(lock_ok($f, $lock), 'a checkout that made it CRLF still holds (core.autocrlf)');
put("one\ntwo changed\n");
ok(!lock_ok($f, $lock), 'a real change does not');
put("one\r\ntwo changed\r\n");
ok(!lock_ok($f, $lock), 'a real change under CRLF does not either');
put("one\r\ntwo\r\n");
my $crlf = sha_file($f);
put("one\ntwo\n");
ok(lock_ok($f, $crlf), 'a lock taken on CRLF holds when the file is LF again');
put("one\r\ntwo\n");
ok(!lock_ok($f, $lock) || 1, 'mixed endings are tolerated or refused, never an error');
ok(!lock_ok("$dir/missing.txt", $lock), 'a missing file does not hold');

# the same through dt: lock a test, let a checkout rewrite its line endings, then verify
new_repo();
dt('init');
dt('engage', 's1');
dt('goal', 'new', 'crlf');
dt('criteria', 'add', '--id', 'C1', '--text', 'WHEN x THEN y', '--check', 'true');
dt('goal', 'confirm', '--lane', 'standard', '--lifecycle', 'agile-kanban');
sh(q{printf 'a\nb\n' > test_a.txt});
my ($rc, $out) = dt('criteria', 'lock', 'test_a.txt');
is($rc, 0, 'lock') or diag $out;
sh(q{perl -pi -e 's/\n/\r\n/' test_a.txt});
($rc, $out) = dt('verify');
unlike($out, qr/LOCK_VIOLATION/, 'verify: a CRLF rewrite is not a violation');
sh(q{printf 'a\nweakened\n' > test_a.txt});
($rc, $out) = dt('verify');
like($out, qr/LOCK_VIOLATION: test_a\.txt/, 'verify: a changed line is');

# --- hooks given Windows paths decide as they do for POSIX ones ---
{
    local $ENV{DT_PLATFORM} = 'msys';
    dt('state', 'transition', 'VERIFYING');
    my ($c, $o2) = hook('state-protect', { session_id => 's1', cwd => $REPO, agent_id => 'a1', agent_type => 'devteam:fullstack-engineer',
        tool_name => 'Write', tool_input => { file_path => "$REPO\\.devteam\\state.json", content => '{}' } });
    is(decision($o2), 'deny', 'a subagent write to state through a backslash path is refused (it was a hole)');
    ($c, $o2) = hook('state-protect', { session_id => 's1', cwd => $REPO, agent_id => 'a1', agent_type => 'devteam:fullstack-engineer',
        tool_name => 'Write', tool_input => { file_path => "$REPO\\src\\app.py", content => 'x' } });
    is($o2, '', 'and an ordinary file is not');
    ($c, $o2) = hook('state-protect', { session_id => 's1', cwd => $REPO, agent_id => 'a1', agent_type => 'devteam:fullstack-engineer',
        tool_name => 'Write', tool_input => { file_path => "$REPO\\.devteam\\adr\\0001-x.md", content => 'x' } });
    is($o2, '', 'an ADR path is still allowed');
}
{
    local $ENV{DT_PLATFORM} = 'linux';
    my ($c, $o2) = hook('state-protect', { session_id => 's1', cwd => $REPO, agent_id => 'a1', agent_type => 'devteam:fullstack-engineer',
        tool_name => 'Write', tool_input => { file_path => "$REPO/.devteam/state.json", content => '{}' } });
    is(decision($o2), 'deny', 'and the POSIX form is refused as before');
}

# --- preflight names the platform ---
{
    local $ENV{DT_PLATFORM} = 'MSWin32';
    my ($c, $o2) = dt('preflight');
    like($o2, qr/^FAIL platform: native Windows perl \(MSWin32\): not supported; run dt and the hooks with Git for Windows' perl/m, 'native Windows perl is named as unsupported');
}
{
    local $ENV{DT_PLATFORM} = 'msys';
    my ($c, $o2) = dt('preflight');
    like($o2, qr/^ok\s+platform: Windows, perl from Git for Windows \(msys\)/m, 'Git for Windows perl is accepted');
}
SKIP: {
    skip 'this is a Windows perl', 1 if $^O =~ /^(?:msys|cygwin|MSWin32)$/;
    my ($c, $o2) = dt('preflight');
    unlike($o2, qr/platform:/, 'elsewhere preflight says nothing about the platform');
}

# --- Chrome is found where Windows installs it ---
{
    my $pf = tempdir(CLEANUP => 1);
    mkdir "$pf/Google"; mkdir "$pf/Google/Chrome"; mkdir "$pf/Google/Chrome/Application";
    my $fake = "$pf/Google/Chrome/Application/chrome.exe";
    open my $h, '>', $fake or die;
    print $h "#!/bin/sh\nfor a in \"\$@\"; do case \"\$a\" in --screenshot=*) f=\"\${a#--screenshot=}\"; echo png > \"\$f\";; esac; done\n";
    close $h;
    chmod 0755, $fake;
    local $ENV{ProgramFiles} = $pf;
    local $ENV{PATH} = '/usr/bin:/bin';
    delete local $ENV{DT_CHROME};
    my ($c, $o2) = dt('shot', '--name', 'win', 'http://127.0.0.1:9/');
    like($o2, qr/win-1280\.png$/m, 'dt shot finds chrome.exe under %ProgramFiles%') or diag $o2;
}

# --- on a real Windows perl: the spellings it uses and a process it cannot see with kill ---
SKIP: {
    skip 'this is not a Windows perl', 5 unless $^O =~ /^(?:msys|cygwin|MSWin32)$/;
    delete local $ENV{DT_PLATFORM};
    is(DT::platform(), $^O eq 'MSWin32' ? 'MSWin32' : 'msys', 'Git for Windows perl is told apart from Cygwin');
    is(native_path('C:\\Users\\me\\x'), $^O eq 'MSWin32' ? 'C:/Users/me/x' : '/c/Users/me/x', 'a drive path gets this perl\'s spelling');
    my $here = native_path(Cwd::getcwd());
    is($here, Cwd::getcwd(), 'the working directory is already in that spelling');
    require DT::Sessions;
    my $pid = fork() // die;
    if (!$pid) { exec 'ping', '-n', '30', '127.0.0.1' or exit 127 }
    select undef, undef, undef, 0.5;
    my $win = -r "/proc/$pid/winpid" ? slurp("/proc/$pid/winpid") : '';
    $win =~ s/\s+//g;
    ok(DT::Sessions::pid_alive($win), "a live process is alive by its Windows pid ($win)") or diag "winpid '$win'";
    kill 'KILL', $pid;
    waitpid($pid, 0);
    select undef, undef, undef, 0.5;
    ok(!DT::Sessions::pid_alive($win), 'and not once it has ended');
}

# --- the repository itself is safe to check out on Windows ---
my $attr = slurp("$FindBin::Bin/../.gitattributes");
like($attr, qr/^\* text=auto eol=lf$/m, '.gitattributes forces LF line endings');
for my $s ("$PLUGIN/hooks/hook.sh", "$PLUGIN/hooks/hook.pl", "$PLUGIN/bin/dt") {
    unlike(slurp($s), qr/\r/, (split m{/}, $s)[-1] . ' has no CR (a CRLF shebang does not start)');
}
my $hooks = decode_json(slurp("$PLUGIN/hooks/hooks.json"));
my @cmds;
for my $ev (values %{ $hooks->{hooks} }) { for my $m (@$ev) { push @cmds, map { $_->{command} } @{ $m->{hooks} } } }
ok(@cmds >= 8, 'hooks.json has its hooks') or diag scalar @cmds;
is(scalar(grep { m{^sh "\$\{CLAUDE_PLUGIN_ROOT\}/hooks/hook\.sh" [a-z-]+$} } @cmds), scalar @cmds,
    'every hook is a shell command that runs sh itself with the plugin root quoted (no PATH, no exec bit)');
is(scalar(grep { ref $_ eq 'HASH' && exists $_->{args} } map { @{ $_->{hooks} } } map { @$_ } values %{ $hooks->{hooks} }), 0, 'and none uses the exec form that needs sh on the Windows PATH');

done_testing;
