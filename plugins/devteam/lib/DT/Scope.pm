package DT::Scope;
# What changed in the working tree since a task started, and whether that task was meant to touch it.
# It reports writes by anyone (the engineer, another session, a tool); it does not decide who made them.
use strict;
use warnings;
use DT qw(root git_out sha_file goal_dir jread jwrite ts);
use Exporter 'import';
our @EXPORT_OK = qw(start load outside accept matches);

my @NOISE = (':!.devteam', ':!.claude/worktrees', ':!.claude/settings.local.json');
sub file { my $g = goal_dir() or die "dt: no active goal\n"; "$g/scope.json" }
sub load { jread(file()) }    # undef until `dt scope start`

# path => content hash (or DELETED) for everything that differs from $base: committed, staged, unstaged, untracked.
sub changed {
    my ($base) = @_;
    my $r = root();
    my $tracked = length $base ? git_out($r, 'diff', '--name-only', '-z', '--no-renames', $base, '--', '.', @NOISE) : '';
    my $new = git_out($r, 'ls-files', '-o', '--exclude-standard', '-z', '--', '.', @NOISE);
    return { map { $_ => (-f "$r/$_" ? sha_file("$r/$_") : 'DELETED') } grep { length } split /\0/, "$tracked\0$new" };
}

# Pattern forms: an exact path, `dir/` (everything below), or a glob with * (one segment) and ** (any depth).
sub matches {
    my ($path, $pat) = @_;
    $pat =~ s{^\./}{};
    return 1 if $path eq $pat || index($path, $pat =~ m{/$} ? $pat : "$pat/") == 0;
    (my $re = quotemeta $pat) =~ s{\\\*\\\*}{.*}g;
    $re =~ s{\\\*}{[^/]*}g;
    $re =~ s{\\\?}{[^/]}g;
    return $path =~ /^$re$/ ? 1 : 0;
}

# Paths changed since the task started that its allowed files do not cover and nobody accepted.
sub outside {
    my ($s) = @_;
    my $now = changed($s->{base});
    my %ok = map { $_ => 1 } @{ $s->{accepted} };
    return sort grep {
        my $p = $_;
        !($s->{snapshot}{$p} && $s->{snapshot}{$p} eq $now->{$p}) && !$ok{$p} && !grep { matches($p, $_) } @{ $s->{allow} };
    } keys %$now;
}

sub start {
    my ($task, @allow) = @_;
    my $prev = load();
    if ($prev) {
        my @open = outside($prev);
        die "dt: the previous task's out-of-scope writes are still unresolved: @open (dt scope check; the user keeps them with dt scope accept)\n" if @open;
    }
    my $base = git_out(root(), 'rev-parse', 'HEAD');
    jwrite(file(), { task => $task, started => ts(), base => $base, allow => \@allow, snapshot => changed($base), accepted => [] });
}

sub accept {
    my ($s, @paths) = @_;
    my %have = map { $_ => 1 } @{ $s->{accepted} };
    push @{ $s->{accepted} }, grep { !$have{$_}++ } @paths;
    jwrite(file(), $s);
}

1;
