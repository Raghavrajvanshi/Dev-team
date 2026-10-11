# Shared helpers for the test files: temp git repo + running dt / hooks with a fixed environment.
use strict;
use warnings;
use File::Temp qw(tempdir);
use FindBin;
use JSON::PP;

our $PLUGIN = "$FindBin::Bin/../plugins/devteam";
our $REPO;

sub new_repo {
    $REPO = tempdir(CLEANUP => 1);
    $ENV{DT_ROOT} = $REPO;
    $ENV{DT_CLAUDE_VERSION} = '2.1.295';
    delete $ENV{CLAUDE_PROJECT_DIR};
    $ENV{DT_CLAUDE_DIR} = tempdir(CLEANUP => 1);    # never read the real session registry or transcripts
    system("cd $REPO && git init -q -b main && git config user.email t\@t.t && git config user.name t && echo hi > a.txt && git add a.txt && git commit -q -m init");
    return $REPO;
}

# Run a command line (string) in the repo; returns (exit, combined output).
sub sh {
    my ($cmd, $stdin) = @_;
    my $in = '';
    if (defined $stdin) { $in = "/tmp/dt-test-stdin-$$.json"; open my $h, '>', $in or die; print $h $stdin; close $h; $in = " < $in" }
    my $out = `cd $REPO && $cmd$in 2>&1`;
    return ($? >> 8, $out);
}
sub q1 { my $s = shift; $s =~ s/'/'\\''/g; "'$s'" }
sub dt { sh("perl $PLUGIN/bin/dt " . join(" ", map { q1($_) } @_)) }
sub hook { my ($name, $json) = @_; sh("perl $PLUGIN/hooks/hook.pl $name", ref $json ? encode_json($json) : $json) }
sub state { decode_json(do { local $/; open my $h, '<', "$REPO/.devteam/state.json" or die; <$h> }) }

1;
