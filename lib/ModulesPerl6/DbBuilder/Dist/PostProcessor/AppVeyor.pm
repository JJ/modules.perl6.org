package ModulesPerl6::DbBuilder::Dist::PostProcessor::AppVeyor;

use strictures 2;
use base 'ModulesPerl6::DbBuilder::Dist::PostProcessor';

use Mojo::UserAgent;
use ModulesPerl6::DbBuilder::Log;
use experimental 'postderef';

sub process {
    my $self = shift;
    my $dist = $self->_dist;

    # Fetch appveyor status only for dists that had new commits in the past 24hr.
    # Unless their cached status is 'unknown' which likely indicates
    # the author did not enable the dist on appveyor yet and the cached status
    # actually exists and not "not set up"
    return if ($dist->{date_updated}//0) < (time - 60*60*24)
        and not $dist->{_builder}{is_fresh} and not $ENV{FULL_REBUILD}
        and $dist->{appveyor_status}
        and not (
            $dist->{appveyor_status} and $dist->{appveyor_status} eq 'unknown'
        );

    unless ( $dist->{_builder}{has_appveyor} ) {
        delete $dist->{appveyor_status}; # toss cached status
        return;
    }

    my ( $user, $repo ) = $dist->{_builder}->@{qw/repo_user  repo/};
    return unless length $user and length $repo;

    my @builds = eval {
        # https://www.appveyor.com/docs/api/projects-builds/#get-project-last-build
        # The API says you always need a Bearer token, but I think
        # that's for the private stuff.
        Mojo::UserAgent->new( max_redirects => 5 )->get(
            "https://ci.appveyor.com/api/projects/$user/$repo/history?recordsNumber=2"
        )->res->json->{builds}->@*;
    }; if ( $@ ) { log error => "Error fetching appveyor status: $@"; return; }

    $dist->{appveyor_status} = $self->_get_appveyor_status( @builds );
    log info => "Determined appveyor status is $dist->{appveyor_status}";

    return 1;
}

sub _get_appveyor_status {
    my ( $self, @builds ) = @_;

    return 'unknown' unless @builds;
    my $state = $builds[0]->{status};

    return $state    if $state =~ /running/;
    # Haven't encountered this one
    # return 'error'   if $state =~ /error/;
    return 'failing' if $state =~ /failed/;
    return 'passing' if $state =~ /success/;
    return 'unknown';
}

1;

__END__

=encoding utf8

=for stopwords md dist dists

=head1 NAME

ModulesPerl6::DbBuilder::Dist::PostProcessor::AppVeyor - postprocessor that determines AppVeyor build status

=head1 SYNOPSIS

    # In your Dist Source:
    $dist->{_builder}{is_fresh}     = 1; # Has new commits
    $dist->{_builder}{has_appveyor} = 1; # Dist has an AppVeyor config file

    # After preprocessor is run:
    say $dist->{appveyor_status}; # says 'passing' for passing Travis builds

=head1 DESCRIPTION

This is a subclass of L<ModulesPerl6::DbBuilder::Dist::PostProcessor> that
implements fetching AppVeyor build information.

=head1 EXPECTED DIST KEYS

=head2 C<{date_updated}>

    $dist->{date_updated} = time;

This boolean key indicates when the dist's last commit was done. The
postprocessor won't attempt to fetch new Travis info for commits older than
24 hours, unless cached Travis status is C<unknown>.

=head2 C<{_builder}{is_fresh}>

    $dist->{_builder}{is_fresh} = 1;

This boolean key indicates a dist has fresh commits (based on the current
data in the database). The presence of this key will trigger Travis info
fetch regardless of the value of C<{date_updated}> key.

=head2 C<{_builder}{has_appveyor}>

    $dist->{_builder}{has_appveyor} = 1;

This boolean key indicates the dist has an AppVeyor configuration file.
This can be either F<appveyor.yml> or F<.appveyor.yml>. If this is not
set, the postprocessor won't run.

=head1 SET DIST KEYS

=head2 C<{appveyor_status}>

    say $dist->{appveyor_status};

After the postprocessor finishes it will set the C<appveyor_status> dist key
to the string indicating the Travis build status (e.g. C<failing>,
C<passing>, C<error>, etc.)

=head1 CONTACT INFORMATION

Original version of this module was written by Zoffix Znet
(L<https://github.com/zoffixznet/>, C<Zoffix> on irc.freenode.net).

=head1 LICENSE

You can use and distribute this module under the same terms as Perl itself.
