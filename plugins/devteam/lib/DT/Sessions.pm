package DT::Sessions;
# Who else is working in this repository, and which session holds the team. Evidence, best first:
#   1. Claude Code's local session registry (<claude dir>/sessions/<pid>.json: pid, sessionId, cwd, status),
#      trusted only when it lists the asking session itself, so a format change degrades instead of misleading;
#   2. the project's transcript files (<claude dir>/projects/<path>/<session>.jsonl), by recency;
#   3. what our own hooks saw other sessions do once the team is engaged (.devteam/sessions.json).
# The aim is to detect and warn, never to prevent: other editors and tools write too.
use strict;
use warnings;
use Cwd qw(abs_path);
use DT qw(root ddir jread jwrite slurp spit locked config_read);
use Exporter 'import';
our @EXPORT_OK = qw(live_others holder_status lease_write lease_touch note_other foreign_writes ack acked probe transcript_file);

sub ttl        { $ENV{DT_LIVE_SECS} // config_read()->{sessions}{live_secs} // 1800 }
sub claude_dir { $ENV{DT_CLAUDE_DIR} // $ENV{CLAUDE_CONFIG_DIR} // ($ENV{HOME} // '') . '/.claude' }
sub real       { my $p = shift; abs_path($p) // $p }
sub store      { ddir() . '/sessions.json' }
sub read_store { eval { jread(store()) } // {} }
sub pid_alive  { my $p = shift; ($p // '') =~ /^\d+$/ && (kill(0, $p) || $!{EPERM}) ? 1 : 0 }

# A session shares our working tree when it runs in this checkout or below it, not in an isolated worktree of it.
sub shares_tree {
    my ($cwd) = @_;
    my ($c, $r) = (real($cwd), real(root()));
    return 0 unless $c eq $r || index($c, "$r/") == 0;
    return index($c, "$r/.claude/worktrees/") == 0 ? 0 : 1;
}

# Live sessions from the registry, and whether the registry can be trusted (it lists $self).
sub registry {
    my ($self) = @_;
    opendir(my $d, claude_dir() . '/sessions') or return ([], 0);
    my (@live, $trusted);
    for my $f (sort grep { /^\d+\.json$/ } readdir $d) {
        my $j = eval { jread(claude_dir() . "/sessions/$f") };
        next unless ref $j eq 'HASH' && length($j->{sessionId} // '') && $j->{pid} && defined $j->{cwd};
        $trusted = 1 if $j->{sessionId} eq $self;
        next unless pid_alive($j->{pid});
        push @live, { id => $j->{sessionId}, pid => $j->{pid}, cwd => $j->{cwd}, name => $j->{name} // '', via => 'registry',
            busy => ($j->{status} // '') eq 'busy' ? 1 : 0, age => int(time - (($j->{updatedAt} // $j->{startedAt} // 0) / 1000)) };
    }
    return (\@live, $trusted ? 1 : 0);
}

sub transcript_dir {
    return $ENV{DT_TRANSCRIPT_DIR} if $ENV{DT_TRANSCRIPT_DIR};
    (my $slug = real(root())) =~ s/[^A-Za-z0-9]/-/g;
    return claude_dir() . "/projects/$slug";
}
sub transcript_file { transcript_dir() . "/$_[0].jsonl" }
sub transcripts {
    my ($self) = @_;
    my $dir = transcript_dir();
    opendir(my $d, $dir) or return ();
    return map { { id => $_->[0], pid => 0, cwd => root(), name => '', via => 'transcript', busy => 0, age => int(time - $_->[1]) } }
      grep { $_->[0] ne $self } map { /^([\w-]+)\.jsonl$/ ? [ $1, (stat "$dir/$_")[9] ] : () } readdir $d;
}

sub observed {
    my ($self) = @_;
    my $seen = read_store()->{seen} // {};
    return map { { id => $_, pid => 0, cwd => root(), name => '', via => 'hooks', busy => 0, age => int(time - $seen->{$_}{ts}) } }
      grep { $_ ne $self } keys %$seen;
}

# Other sessions that may be writing to this working tree right now, freshest first.
sub live_others {
    my ($self) = @_;
    $self //= '';
    my ($reg, $trusted) = registry($self);
    my @found = ($trusted ? (grep { $_->{id} ne $self && shares_tree($_->{cwd}) } @$reg) : transcripts($self), observed($self));
    my %best;
    for my $e (@found) {
        my $o = $best{ $e->{id} };
        $best{ $e->{id} } = $e if !$o || ($e->{via} eq 'registry' && $o->{via} ne 'registry') || ($e->{via} eq $o->{via} && $e->{age} < $o->{age});
    }
    return sort { $a->{age} <=> $b->{age} } grep { $_->{busy} || $_->{age} <= ttl() } values %best;
}

# The lease: .devteam/session.lock holds the holder's session id and its mtime is the heartbeat.
sub lock_file  { ddir() . '/session.lock' }
sub lease_write { spit(lock_file(), "$_[0]\n") }
sub lease_touch { my $f = lock_file(); utime(undef, undef, $f) if -f $f }
sub lease_age {
    my ($sid) = @_;
    my $c = slurp(lock_file());
    return unless defined $c;
    $c =~ s/\s+\z//;
    return $c eq $sid ? int(time - (stat lock_file())[9]) : undef;
}

# Is the session that holds the team still around? The registry decides when it lists us, heartbeats otherwise.
sub holder_status {
    my ($holder, $self) = @_;
    $self //= '';
    my ($reg, $trusted) = registry($self);
    if ($trusted) {
        my ($h) = grep { $_->{id} eq $holder } @$reg;
        return { live => 0, why => 'that session is no longer running' } unless $h;
        my $live = $h->{busy} || $h->{age} <= ttl() ? 1 : 0;
        return { live => $live, age => $h->{age}, why => $h->{busy} ? 'running and busy' : "last active $h->{age}s ago" };
    }
    my ($age) = sort { $a <=> $b } grep { defined } lease_age($holder), map { $_->{age} } grep { $_->{id} eq $holder } transcripts($self);
    return { live => 0, why => 'no sign of that session' } unless defined $age;
    return { live => $age <= ttl() ? 1 : 0, age => $age, why => "last heard from it $age" . 's ago' };
}

# Hook-side record of another session's activity, with the file it was about to write when known.
sub note_other {
    my ($sid, $path) = @_;
    return unless length($sid // '');
    locked(sub {
        my $s = read_store();
        my $e = $s->{seen}{$sid} //= { ts => 0, writes => [] };
        return if !defined $path && time - $e->{ts} < 10;
        $e->{ts} = time;
        if (defined $path) {
            push @{ $e->{writes} }, { path => $path, ts => time };
            shift @{ $e->{writes} } while @{ $e->{writes} } > 30;
        }
        delete $s->{seen}{$_} for grep { time - $s->{seen}{$_}{ts} > 7 * 86400 } keys %{ $s->{seen} };
        jwrite(store(), $s);
    });
}
sub foreign_writes {
    my $seen = read_store()->{seen} // {};
    return sort { $b->{ts} <=> $a->{ts} } map { my $id = $_; map { { session => $id, %$_ } } @{ $seen->{$id}{writes} // [] } } keys %$seen;
}

# Acknowledgements are per goal: "I know about that session, carry on" is a choice for this goal only.
sub ack {
    my ($goal, @ids) = @_;
    locked(sub { my $s = read_store(); $s->{acked}{$goal}{$_} = time for @ids; jwrite(store(), $s) });
}
sub acked { my ($goal) = @_; return %{ read_store()->{acked}{$goal} // {} } }

# What this machine can tell us, for `dt sessions probe` and the self-test.
sub probe {
    my ($self) = @_;
    my ($reg, $trusted) = registry($self);
    my $dir = claude_dir() . '/sessions';
    my @r = (-d $dir ? ($trusted ? "registry: ok ($dir lists this session; " . scalar(@$reg) . ' live)' : "registry: not usable ($dir exists but does not list this session)")
                     : "registry: absent ($dir)");
    my $t = transcript_dir();
    push @r, -f "$t/$self.jsonl" ? "transcripts: ok ($t has this session's transcript)" : (-d $t ? "transcripts: dir found but no file for this session ($t)" : "transcripts: absent ($t)");
    return @r;
}

1;
