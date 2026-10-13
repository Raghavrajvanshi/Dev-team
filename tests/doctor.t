use strict;
use warnings;
use FindBin;
use JSON::PP;
use File::Temp qw(tempdir);
use Test::More;
require "$FindBin::Bin/lib.pl";
our ($PLUGIN, $REPO);

# `dt doctor` (gap G12): each fault in an install is named with a plain fix. Faults are made in a copy of the plugin.
sub slurp { open my $h, '<:raw', $_[0] or die "$_[0]: $!"; local $/; <$h> }
sub spit  { open my $h, '>:raw', $_[0] or die "$_[0]: $!"; print $h $_[1]; close $h }

my $WORK = tempdir(CLEANUP => 1);
my $n = 0;
sub fresh_plugin {
    my $d = "$WORK/p" . $n++;
    system("mkdir -p $d && cp -R $PLUGIN $d/devteam") == 0 or die;
    return "$d/devteam";
}
# a PATH with git (it is under /mingw64 in Git for Windows) and the system tools, and no dt
my ($GIT) = `sh -c 'command -v git'` =~ m{^(.*)/git(?:\.exe)?\s*$};
sub base_path { join ':', grep { length } $GIT, '/usr/bin', '/bin' }
sub on_path   { "$_[0]/bin:" . base_path() }    # a PATH that finds this plugin copy's dt, as Claude Code's does
sub doctor {
    my ($plugin, %e) = @_;
    my %env = (DT_CLAUDE_VERSION => '2.1.296', DT_LATEST_RELEASE => '', PATH => base_path(), %e);
    delete $env{$_} for grep { !defined $env{$_} } keys %env;
    my $set = join ' ', map { "$_=" . q1($env{$_}) } sort keys %env;
    my $args = delete $env{ARGS} // '--offline';
    return sh("cd $REPO && env -i HOME=$ENV{HOME} DT_ROOT=$REPO $set perl $plugin/bin/dt doctor $args");
}
sub version { decode_json(slurp("$_[0]/.claude-plugin/plugin.json"))->{version} }

new_repo();

# --- a healthy install: every line ok, a zero exit ---
my $p = fresh_plugin();
my ($rc, $out) = doctor($p, PATH => on_path($p), ARGS => '--offline');
is($rc, 0, 'a healthy install exits 0') or diag $out;
like($out, qr/^devteam doctor: plugin \S+ at \S+/m, 'it says which plugin and where');
like($out, qr/^ok\s+claude: 2\.1\.296 \(need >= 2\.1\.295\)$/m, 'claude is checked');
like($out, qr/^ok\s+perl: /m, 'perl and its core modules');
like($out, qr/^ok\s+git: /m, 'git');
like($out, qr/^ok\s+files: \d+ skills, \d+ agents, \d+ lifecycles$/m, 'the plugin\'s files');
like($out, qr/^ok\s+line-endings: LF in every script$/m, 'line endings');
like($out, qr/^ok\s+hooks\.json: \d+ hooks, every handler exists$/m, 'every hook names a handler that exists');
like($out, qr/^ok\s+hooks-run: \d+ hooks started and answered cleanly: .*guard.*state-protect/m, 'every hook is started the way Claude Code starts it');
like($out, qr/^ok\s+dt: resolves to this plugin's bin\/dt$/m, 'dt on PATH is this plugin\'s');
like($out, qr/^info\s+latest-release: not checked \(--offline\)$/m, '--offline skips the network');
like($out, qr/^all checks passed$|^no problems, \d+ warning/m, 'and ends with a verdict');
unlike($out, qr/^FAIL|^warn\s+(?!installed)/m, 'with nothing to fix');
unlike($out, qr/fix:/, 'so no fix lines');

# --- the machine ---
($rc, $out) = doctor($p, PATH => on_path($p), DT_CLAUDE_VERSION => '2.1.200');
isnt($rc, 0, 'an old claude fails');
like($out, qr/^FAIL claude: 2\.1\.200 is older than 2\.1\.295.*\n\s+fix: run: claude update, then restart Claude Code$/m, 'and says how to fix it');
($rc, $out) = doctor($p, PATH => on_path($p), DT_PLATFORM => 'MSWin32');
like($out, qr/^FAIL platform: this is a native Windows perl.*\n\s+fix: run dt and the hooks with the perl that comes with Git for Windows/m, 'a native Windows perl is refused with the way out');
($rc, $out) = doctor($p, PATH => on_path($p), DT_PLATFORM => 'msys');
like($out, qr/^ok\s+platform: Windows with the perl from Git for Windows \(msys\)$/m, 'Git for Windows perl is accepted');

# --- the plugin's own files ---
my $q = fresh_plugin();
unlink "$q/hooks/hook.pl";
($rc, $out) = doctor($q, PATH => on_path($q));
isnt($rc, 0, 'a missing file fails');
like($out, qr/^FAIL files: the plugin folder is incomplete: missing hooks\/hook\.pl\n\s+fix: reinstall it: claude plugin uninstall/m, 'it names the file and the reinstall');
like($out, qr/^FAIL hooks-run: .*(?:exit|stderr)/m, 'and the hooks that need it do not run');

$q = fresh_plugin();
spit("$q/hooks/hook.sh", join("\r\n", split /\n/, slurp("$q/hooks/hook.sh")) . "\r\n");
($rc, $out) = doctor($q, PATH => on_path($q));
like($out, qr/^FAIL line-endings: CRLF line endings in hooks\/hook\.sh \(a script with CRLF does not start\)\n\s+fix: reinstall the plugin; if you cloned it yourself, run: git config core\.autocrlf false/m, 'CRLF in a script is named');
SKIP: {
    skip 'the sh of Git for Windows ignores the CR (igncr), so the hooks still run there', 1 if $^O =~ /^(?:msys|cygwin|MSWin32)$/;
    like($out, qr/^FAIL hooks-run: /m, 'and shows up as hooks that do not run (or that do nothing, silently)');
}

$q = fresh_plugin();
my $hj = slurp("$q/hooks/hooks.json");
$hj =~ s/hook\.sh\\" guard"/hook.sh\\" bogus"/;
spit("$q/hooks/hooks.json", $hj);
($rc, $out) = doctor($q, PATH => on_path($q));
like($out, qr/^FAIL hooks\.json: names a hook that does not exist: PreToolUse: sh .*bogus/m, 'a hook that names no handler is named');

$q = fresh_plugin();
spit("$q/lib/Hooks.pm", slurp("$q/lib/Hooks.pm") . "\nsyntax error here (\n");
($rc, $out) = doctor($q, PATH => on_path($q));
like($out, qr/^FAIL hooks-code: lib\/Hooks\.pm does not load: /m, 'a broken Hooks.pm is named, not a crash');
like($out, qr/^\d+ problem\(s\)/m, 'and the doctor still finishes');

# --- dt on PATH ---
($rc, $out) = doctor($p, PATH => base_path());
like($out, qr/^warn dt: dt is not on PATH in this shell\n\s+fix: inside Claude Code the plugin's bin\/ joins PATH.*restart Claude Code or run \/reload-plugins/m, 'dt missing from PATH is a warning with the way to run it');
is($rc, 0, 'which is not a failure');
my $old = "$WORK/old";
mkdir $old;
spit("$old/dt", "#!/bin/sh\necho old\n");
chmod 0755, "$old/dt";
($rc, $out) = doctor($p, PATH => "$old:" . base_path());
like($out, qr/^FAIL dt: another dt comes first on PATH: \S+old\/dt \(this plugin's is \S+\/bin\/dt\)\n\s+fix: an older dt runs old scripts under the new skills/m, 'a stale dt first on PATH fails');

# --- versions ---
my $v = version($p);
($rc, $out) = doctor($p, PATH => on_path($p), DT_LATEST_RELEASE => '99.0.0', ARGS => '');
like($out, qr/^warn version: this copy is \Q$v\E and 99\.0\.0 is released\n\s+fix: run: claude plugin marketplace update devteam-marketplace && claude plugin update devteam\@devteam-marketplace, then restart Claude Code$/m, 'a newer release is a warning with the update commands');
($rc, $out) = doctor($p, PATH => on_path($p), DT_LATEST_RELEASE => $v, ARGS => '');
like($out, qr/^ok\s+version: \Q$v\E is the latest release$/m, 'the same version is ok');
($rc, $out) = doctor($p, PATH => on_path($p), DT_LATEST_RELEASE => '0.0.1', ARGS => '');
like($out, qr/^ok\s+version: \Q$v\E is ahead of the latest release 0\.0\.1 \(a development copy\)$/m, 'a newer copy than the release is a development copy');

# the network is used only when asked: --offline never calls curl, and without it curl is the source
my $bin = "$WORK/net";
mkdir $bin;
spit("$bin/curl", "#!/bin/sh\ntouch $WORK/curl.called\necho '{\"tag_name\":\"v99.1.2\"}'\n");
chmod 0755, "$bin/curl";
($rc, $out) = doctor($p, PATH => "$bin:" . on_path($p), ARGS => '--offline', DT_LATEST_RELEASE => undef);
ok(!-e "$WORK/curl.called", '--offline makes no request');
($rc, $out) = doctor($p, PATH => "$bin:" . on_path($p), ARGS => '', DT_LATEST_RELEASE => undef);
ok(-e "$WORK/curl.called", 'without it the latest release is asked for');
like($out, qr/^warn version: this copy is \Q$v\E and 99\.1\.2 is released$/m, 'and its answer is used');
spit("$bin/curl", "#!/bin/sh\nexit 22\n");
($rc, $out) = doctor($p, PATH => "$bin:" . on_path($p), ARGS => '', DT_LATEST_RELEASE => undef);
like($out, qr/^info\s+latest-release: could not reach GitHub/m, 'an unreachable GitHub is information, not a failure');
is($rc, 0, 'and the exit is still 0');

# --- what is installed ---
sub listing { my $f = "$WORK/list" . $n++ . '.json'; spit($f, encode_json($_[0])); $f }
($rc, $out) = doctor($p, PATH => on_path($p), DT_LATEST_RELEASE => '0.2.15', ARGS => '',
    DT_PLUGIN_LIST_JSON => listing([ { id => 'devteam@devteam-marketplace', version => '0.2.3', scope => 'user', enabled => JSON::PP::true } ]));
like($out, qr/^warn installed: devteam\@devteam-marketplace 0\.2\.3 \(user scope\) is behind the latest release 0\.2\.15\n\s+fix: run: claude plugin marketplace update/m, 'an installed copy that is behind is a warning');
($rc, $out) = doctor($p, PATH => on_path($p), DT_LATEST_RELEASE => $v, ARGS => '',
    DT_PLUGIN_LIST_JSON => listing([ { id => 'devteam@devteam-marketplace', version => $v, scope => 'user', enabled => JSON::PP::false } ]));
like($out, qr/^warn installed: .*is installed but disabled\n\s+fix: run: claude plugin enable devteam\@devteam-marketplace$/m, 'a disabled install says so');
($rc, $out) = doctor($p, PATH => on_path($p), DT_LATEST_RELEASE => $v, ARGS => '',
    DT_PLUGIN_LIST_JSON => listing([ map { { id => 'devteam@devteam-marketplace', version => $v, scope => $_, enabled => JSON::PP::true } } qw(user project) ]));
like($out, qr/^warn installed: devteam is installed in 2 scopes \(user, project\): its hooks may run twice\n\s+fix: keep one: claude plugin uninstall/m, 'two scopes are named');
($rc, $out) = doctor($p, PATH => on_path($p), DT_LATEST_RELEASE => $v, ARGS => '',
    DT_PLUGIN_LIST_JSON => listing([ { id => 'other@x', version => '1', scope => 'user', enabled => JSON::PP::true } ]));
like($out, qr/^info\s+installed: this copy is not installed as a plugin \(it runs from /m, 'a copy that is not installed is information');
($rc, $out) = doctor($p, PATH => on_path($p), DT_LATEST_RELEASE => $v, ARGS => '',
    DT_PLUGIN_LIST_JSON => listing([ { id => 'devteam@devteam-marketplace', version => '0.0.9', scope => 'user', enabled => JSON::PP::true } ]));
like($out, qr/^warn installed: .*0\.0\.9 .* is behind the latest release/m, 'an installed copy older than this one is behind too');

# --- the project ---
dt('init');
($rc, $out) = doctor($p, PATH => on_path($p));
like($out, qr/^ok\s+project: devteam at \S+: not engaged$/m, 'a project that has devteam is described');
like($out, qr/^warn setup: incomplete \(models not chosen; no project profile; no standards\)\n\s+fix: run \/devteam:start; setup runs once$/m, 'unfinished setup is a warning');
dt('engage', 's1');
sh(q{perl -MJSON::PP -e 'open F,"<.devteam/config.json"; local $/; $c=decode_json(<F>); close F; $c->{trace}=JSON::PP::true; open O,">.devteam/config.json"; print O JSON::PP->new->canonical->pretty->encode($c)'});
($rc, $out) = doctor($p, PATH => on_path($p));
like($out, qr/^FAIL project: .*engaged.*protected files changed outside dt: \.devteam\/config\.json\n\s+fix: review those files, then run: dt resync$/m, 'a tampered protected file fails');
isnt($rc, 0, 'with a non-zero exit');
dt('resync');
sh('echo not-json >> .devteam/config.json');
($rc, $out) = doctor($p, PATH => on_path($p));
like($out, qr/^FAIL project: devteam's state or config in \S+ cannot be read: garbage after JSON.*\n\s+fix: restore state\.json and config\.json from a backup/m, 'a config that is not JSON is named, not a crash');
sh('git checkout -q .devteam/config.json 2>/dev/null; rm -rf .devteam');
dt('init');
dt('engage', 's1');

# --- read-only: the hooks it runs never touch the real project, even with DT_ROOT pointing at it ---
dt('init');
dt('engage', 's1');
sh(q{perl -MJSON::PP -e 'open F,"<.devteam/config.json"; local $/; $c=decode_json(<F>); close F; $c->{trace}=JSON::PP::true; open O,">.devteam/config.json"; print O JSON::PP->new->canonical->pretty->encode($c)'});
my $seal_before = slurp("$REPO/.devteam/seal.json");
my $log_before = -f "$REPO/.devteam/log.jsonl" ? slurp("$REPO/.devteam/log.jsonl") : '';
($rc, $out) = doctor($p, PATH => on_path($p));
is(slurp("$REPO/.devteam/seal.json"), $seal_before, 'the doctor leaves the real seal alone (a hook would have accepted the edit)');
is(-f "$REPO/.devteam/log.jsonl" ? slurp("$REPO/.devteam/log.jsonl") : '', $log_before, 'and writes nothing to the real ledger');
like($out, qr/^FAIL project: /m, 'while still reporting the edit');

# --- written parts, and who may run it ---
my $skill = slurp("$PLUGIN/skills/doctor/SKILL.md");
cmp_ok(scalar(() = $skill =~ /\n/g), '<=', 15, 'the skill is short');
like($skill, qr/Run `dt doctor`.*`--offline`/s, 'it runs the command and knows --offline');
like($skill, qr/Never run an install, update, uninstall or disable command yourself/, 'it never changes the installation unasked');
my ($c, $o2) = hook('git-guard', { session_id => 's1', cwd => $REPO, agent_id => 'a1', agent_type => 'devteam:reviewer', tool_name => 'Bash', tool_input => { command => 'dt doctor' } });
like($o2, qr/permissionDecision.*deny/s, 'a subagent does not run it (it is the PM\'s and the user\'s)');
like(slurp("$FindBin::Bin/../README.md"), qr/\/devteam:doctor/, 'the README lists the command');
unlike(slurp("$FindBin::Bin/../README.md"), qr/\*\*Status: v0\.1/, 'and no longer calls itself v0.1');

done_testing;
