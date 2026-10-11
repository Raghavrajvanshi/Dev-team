use strict;
use warnings;
use FindBin;
use JSON::PP;
use File::Temp qw(tempdir);
use Test::More;
require "$FindBin::Bin/lib.pl";
use lib "$FindBin::Bin/../plugins/devteam/lib";
use DT qw(usage_since);
our $REPO;

# Token accounting: Claude Code writes a message's usage once per content block, and a fork's transcript carries
# its parent's history. Counting every line over-stated usage about threefold on a real session.
my $dir = tempdir(CLEANUP => 1);
my $f = "$dir/t.jsonl";
sub msg {
    my %a = (sid => 'S1', model => 'claude-sonnet-5-5', in => 1, out => 10, cr => 100, cw => 5, @_);
    return encode_json({ type => 'assistant', sessionId => $a{sid}, requestId => $a{req} // "req_$a{id}",
        message => { id => $a{id}, model => $a{model}, usage => { input_tokens => $a{in}, output_tokens => $a{out},
            cache_read_input_tokens => $a{cr}, cache_creation_input_tokens => $a{cw} } } }) . "\n";
}
sub put { open my $h, '>>', $f or die; print $h @_; close $h }
sub reset_file { unlink $f; put('') }
sub sum { my ($t, $k) = @_; my $n = 0; $n += $_->{$k} // 0 for values %$t; $n }

# --- one message, several content blocks: counted once ---
reset_file();
put(msg(id => 'm1') x 4, msg(id => 'm2', out => 20));
my ($t, $off) = usage_since($f, 0);
is(sum($t, 'output'), 30, 'four blocks of one message plus another message: 10 + 20');
is(sum($t, 'cache_read'), 200, 'cache reads are counted once per message too');
is($t->{'claude-sonnet-5-5'}{cache_write}, 10, 'and cache writes');

# --- lines that merely mention usage are ignored ---
put(encode_json({ type => 'user', message => { role => 'user', content => 'the "usage" field of the "usage" report' } }), "\n",
    "not json at all \"usage\"\n");
($t) = usage_since($f, 0);
is(sum($t, 'output'), 30, 'user lines and garbage that contain the word usage add nothing');

# --- a fork's inherited history belongs to another session ---
reset_file();
put(msg(id => 'old1', sid => 'PARENT', out => 1000), msg(id => 'm1', sid => 'S1', out => 10));
($t) = usage_since($f, 0, session => 'S1');
is(sum($t, 'output'), 10, 'with a session given, another session\'s lines are skipped');
($t) = usage_since($f, 0);
is(sum($t, 'output'), 1010, 'without one (a subagent transcript) every line counts');

# --- incremental reads, including a message that straddles two of them ---
reset_file();
put(msg(id => 'm1'), msg(id => 'm2'));
($t, $off, my $last) = usage_since($f, 0, session => 'S1');
is(sum($t, 'output'), 20, 'first read');
is($last, 'm2:req_m2', 'it reports the last message it saw');
put(msg(id => 'm2'), msg(id => 'm3'));    # the rest of m2's blocks arrive, then a new message
my ($t2, $off2) = usage_since($f, $off, session => 'S1', after => $last);
is(sum($t2, 'output'), 10, 'the second read counts only the new message');
is($off2, -s $f, 'and moves the offset to the end');
my $partial = '{"message":{"id":"m9","usage":{"output_tokens":7}}';    # a line still being written
put($partial);
my ($t3, $off3) = usage_since($f, $off2);
is(sum($t3, 'output'), 0, 'an unfinished last line is not counted');
is($off3, $off2, 'and is not consumed');

# --- messages without ids still count (older or unusual lines) ---
reset_file();
put(encode_json({ message => { model => 'm', usage => { output_tokens => 3 } } }), "\n") for 1 .. 2;
($t) = usage_since($f, 0);
is(sum($t, 'output'), 6, 'no id, no dedup');

# --- the hook and `dt engage` wire it together ---
new_repo();
my $trans = tempdir(CLEANUP => 1);
$ENV{DT_TRANSCRIPT_DIR} = $trans;
my $tf = "$trans/S1.jsonl";
open my $h, '>', $tf or die;
print $h msg(id => 'history', sid => 'S1', out => 5000);    # in the session before the team was engaged
close $h;
my ($rc, $out);
dt('init');
($rc, $out) = dt('engage', 'S1');
is($rc, 0, 'engage') or diag $out;
ok(-f "$REPO/.devteam/ledger.offset.main-S1", 'engage took a baseline');
sub stop_hook { hook('ledger', { session_id => 'S1', hook_event_name => 'Stop', transcript_path => $tf }) }
stop_hook();
($rc, $out) = dt('ledger');
unlike($out, qr/claude-sonnet-5-5/, 'nothing since engagement yet: the history is not counted');
open $h, '>>', $tf or die;
print $h msg(id => 'a', out => 40) x 3, msg(id => 'p', sid => 'PARENT', out => 9999), msg(id => 'b', out => 2);
close $h;
stop_hook();
($rc, $out) = dt('ledger');
like($out, qr/claude-sonnet-5-5: in=2 out=42 cache_read=200/, 'two messages counted once each, the other session\'s line not at all');
stop_hook();
($rc, $out) = dt('ledger');
like($out, qr/out=42 /, 'a repeat Stop adds nothing');

# a subagent is counted from the start of its own transcript, once per message
my $af = "$dir/agent.jsonl";
open $h, '>', $af or die;
print $h msg(id => 's1', sid => 'PARENT', out => 7) x 3, msg(id => 's2', sid => 'PARENT', out => 8);
close $h;
hook('ledger', { session_id => 'S1', hook_event_name => 'SubagentStop', agent_id => 'a1', agent_type => 'devteam:reviewer', agent_transcript_path => $af });
my $log = do { local (@ARGV, $/) = "$REPO/.devteam/log.jsonl"; <> };
my ($rec) = grep { /"agent_id":"a1"/ } split /\n/, $log;
is(decode_json($rec)->{tokens}{'claude-sonnet-5-5'}{output}, 15, 'subagent usage: 7 + 8, though its transcript repeats lines and names the parent session');

done_testing;
