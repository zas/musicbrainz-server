package MusicBrainz::Server::Controller::WS::2;

use Moose;
BEGIN { extends 'MusicBrainz::Server::Controller'; }

use MusicBrainz::Server::WebService::XMLSerializer;
use MusicBrainz::Server::WebService::XMLSearch qw( xml_search );
use MusicBrainz::Server::WebService::Validator;
use MusicBrainz::Server::Validation qw( is_valid_isrc is_valid_iswc is_valid_discid );
use Readonly;
use Data::OptList;

Readonly our $MAX_ITEMS => 25;

# This defines what options are acceptable for WS calls.
# Note that the validator will automatically add inc= arguments to the allowed list
# based on other inc= arguments.  (puids are allowed if recordings are allowed, etc..)
my $ws_defs = Data::OptList::mkopt([
     artist => {
                         method   => 'GET',
                         required => [ qw(query) ],
                         optional => [ qw(limit offset) ]
     },
     artist => {
                         method   => 'GET',
                         linked   => [ qw(recording release release-group work) ],
                         inc      => [ qw(aliases) ],
     },
     artist => {
                         method   => 'GET',
                         inc      => [ qw(recordings releases release-groups works
                                          aliases various-artists
                                          _relations tags user-tags ratings user-ratings) ],
     },
     label => {
                         method   => 'GET',
                         required => [ qw(query) ],
                         optional => [ qw(limit offset) ]
     },
     label => {
                         method   => 'GET',
                         inc      => [ qw(releases aliases
                                          _relations tags user-tags ratings user-ratings) ],
     },
     recording => {
                         method   => 'GET',
                         required => [ qw(query) ],
                         optional => [ qw(limit offset) ]
     },
     recording => {
                         method   => 'GET',
                         linked   => [ qw(artist release) ],
                         inc      => [ qw(artist-credits puids isrcs) ],
                         optional => [ qw(limit offset) ]
     },
     recording => {
                         method   => 'GET',
                         inc      => [ qw(artists releases artist-credits puids isrcs
                                          _relations tags user-tags ratings user-ratings) ]
     },
     release => {
                         method   => 'GET',
                         required => [ qw(query) ],
                         optional => [ qw(limit offset) ]
     },
     release => {
                         method   => 'GET',
                         inc      => [ qw(artists labels recordings release-groups
                                          artist-credits discids media _relations) ]
     },
     "release-group" => {
                         method   => 'GET',
                         required => [ qw(query) ],
                         optional => [ qw(limit offset) ]
     },
     "release-group" => {
                         method   => 'GET',
                         inc      => [ qw(artists releases artist-credits
                                          _relations tags user-tags ratings user-ratings) ]
     },
     work => {
                         method   => 'GET',
                         required => [ qw(query) ],
                         optional => [ qw(limit offset) ]
     },
     work => {
                         method   => 'GET',
                         inc      => [ qw(artists aliases artist-credits
                                          _relations tags user-tags ratings user-ratings) ]
     },
     discid => {
                         method   => 'GET',
                         inc      => [ qw(artists labels recordings release-groups artist-credits
                                          puids isrcs _relations) ]
     },
     puid => {
                         method   => 'GET',
                         inc      => [ qw(artists releases puids isrcs artist-credits
                                          _relations tags user-tags ratings user-ratings) ]
     },
     isrc => {
                         method   => 'GET',
                         inc      => [ qw(artists releases puids isrcs artist-credits
                                          _relations tags user-tags ratings user-ratings) ]
     },
     iswc => {
                         method   => 'GET',
                         inc      => [ qw(artists aliases artist-credits
                                          _relations tags user-tags ratings user-ratings) ]
     },
]);

with 'MusicBrainz::Server::WebService::Validator' =>
{
     defs => $ws_defs
};

Readonly my %serializers => (
    xml => 'MusicBrainz::Server::WebService::XMLSerializer',
);

sub bad_req : Private
{
    my ($self, $c) = @_;
    $c->res->status(400);
    $c->res->content_type("text/plain; charset=utf-8");
    $c->res->body($c->stash->{serializer}->output_error($c->stash->{error}.
                  "\nFor usage, please see: http://musicbrainz.org/development/mmd\015\012"));
}

sub unauthorized : Private
{
    my ($self, $c) = @_;
    $c->res->status(401);
    $c->res->content_type("text/plain; charset=utf-8");
    $c->res->body($c->stash->{serializer}->output_error("\nYour credentials ".
        "could not be verified.\nEither you supplied the wrong credentials ".
        "(e.g., bad password), or your client doesn't understand how to ".
        "supply the credentials required."));
}

sub not_found : Private
{
    my ($self, $c) = @_;
    $c->res->status(404);
}

sub begin : Private
{
}

sub end : Private
{
}

sub root : Chained('/') PathPart("ws/2") CaptureArgs(0)
{
    my ($self, $c) = @_;

    $self->validate($c, \%serializers) or $c->detach('bad_req');

    $c->authenticate({}, 'webservice') if ($c->stash->{authorization_required});
}

sub _tags_and_ratings
{
    my ($self, $c, $modelname, $entity, $opts) = @_;

    my $model = $c->model($modelname);

    if ($c->stash->{inc}->tags)
    {
        my @tags = $model->tags->find_tags($entity->id);
        $opts->{tags} = $tags[0];
    }

    if ($c->stash->{inc}->user_tags)
    {
        my @tags = $model->tags->find_user_tags($c->user->id, $entity->id);
        $opts->{user_tags} = \@tags;
    }

    if ($c->stash->{inc}->ratings)
    {
        $model->load_meta($entity);
        if ($entity->rating_count)
        {
            $opts->{ratings} = {
                rating => $entity->rating * 5 / 100,
                count => $entity->rating_count,
            };
        }
    }

    if ($c->stash->{inc}->user_ratings)
    {
        $model->rating->load_user_ratings($c->user->id, $entity);
        $opts->{user_ratings} = $entity->user_rating * 5 / 100;
    }
}

sub _limit_and_offset
{
    my ($self, $c) = @_;

    my $args = $c->stash->{args};
    my $limit = $args->{limit} ? $args->{limit} : 25;
    my $offset = $args->{offset} ? $args->{offset} : 0;

    return ($limit > 100 ? 100 : $limit, $offset);
}

sub make_list
{
    my ($self, $results, $total, $offset) = @_;

    return {
        items => $results,
        total => defined $total ? $total : scalar @$results,
        offset => defined $offset ? $offset : 0
    };
}

sub linked_recordings
{
    my ($self, $c, $opts, $recordings) = @_;

    for my $recording (@$recordings)
    {
        if ($c->stash->{inc}->isrcs)
        {
            my @isrcs = $c->model('ISRC')->find_by_recording([ $recording->id ]);
            $opts->{isrcs} = \@isrcs;
        }
        if ($c->stash->{inc}->puids)
        {
            my @puids = $c->model('RecordingPUID')->find_by_recording($recording->id);
            $opts->{puids} = \@puids;
        }
    }

    if ($c->stash->{inc}->artist_credits)
    {
        $c->model('ArtistCredit')->load(@$recordings);
    }
}

sub linked_release_groups
{
    my ($self, $c, $opts, $release_groups) = @_;

    $c->model('ReleaseGroupType')->load(@$release_groups);

    if ($c->stash->{inc}->artist_credits)
    {
        $c->model('ArtistCredit')->load(@$release_groups);
    }
}

sub linked_releases
{
    my ($self, $c, $opts, $releases) = @_;

    $c->model('ReleaseStatus')->load(@$releases);
    $c->model('ReleasePackaging')->load(@$releases);

    $c->model('Language')->load(@$releases);
    $c->model('Script')->load(@$releases);
    $c->model('Country')->load(@$releases);

    my @mediums;
    if ($c->stash->{inc}->media)
    {
        $c->model('Medium')->load_for_releases(@$releases);

        @mediums = map { $_->all_mediums } @$releases;

        $c->model('MediumFormat')->load(@mediums);
    }

    if ($c->stash->{inc}->discids)
    {
        my @medium_cdtocs = $c->model('MediumCDTOC')->load_for_mediums(@mediums);
        $c->model('CDTOC')->load(@medium_cdtocs);
    }

    if ($c->stash->{inc}->artist_credits)
    {
        $c->model('ArtistCredit')->load(@$releases);
    }
}

sub linked_artists
{
    my ($self, $c, $opts, $artists) = @_;
}

sub linked_labels
{
    my ($self, $c, $opts, $labels) = @_;
}

sub linked_works
{
    my ($self, $c, $opts, $works) = @_;

    if ($c->stash->{inc}->artist_credits)
    {
        $c->model('ArtistCredit')->load(@$works);
    }
}


sub artist : Chained('root') PathPart('artist') Args(1)
{
    my ($self, $c, $gid) = @_;

    if (!$gid || !MusicBrainz::Server::Validation::IsGUID($gid))
    {
        $c->stash->{error} = "Invalid mbid.";
        $c->detach('bad_req');
    }

    my $artist = $c->model('Artist')->get_by_gid($gid);
    unless ($artist) {
        $c->detach('not_found');
    }

    my $opts = {};
    $self->linked_artists ($c, $opts, [ $artist ]);

    $c->model('ArtistType')->load($artist);
    $c->model('Gender')->load($artist);
    $c->model('Country')->load($artist);

    if ($c->stash->{inc}->aliases)
    {
        $opts->{aliases} = $c->model('Artist')->alias->find_by_entity_id($artist->id);
    }

    if ($c->stash->{inc}->recordings)
    {
        my @results = $c->model('Recording')->find_by_artist($artist->id, $MAX_ITEMS);
        $opts->{recordings} = $self->make_list (@results);

        $self->linked_recordings ($c, $opts, $opts->{recordings}->{items});
    }

    if ($c->stash->{inc}->releases)
    {
        my @results;
        if ($c->stash->{inc}->various_artists)
        {
            @results = $c->model('Release')->find_for_various_artists($artist->id, $MAX_ITEMS);
        }
        else
        {
            @results = $c->model('Release')->find_by_artist($artist->id, $MAX_ITEMS);
        }

        $opts->{releases} = $self->make_list (@results);

        $self->linked_releases ($c, $opts, $opts->{releases}->{items});
    }

    if ($c->stash->{inc}->release_groups)
    {
        my @results = $c->model('ReleaseGroup')->find_by_artist($artist->id, $MAX_ITEMS);
        $opts->{release_groups} = $self->make_list (@results);

        $self->linked_release_groups ($c, $opts, $opts->{release_groups}->{items});
    }

    if ($c->stash->{inc}->works)
    {
        my @results = $c->model('Work')->find_by_artist($artist->id, $MAX_ITEMS);
        $opts->{works} = $self->make_list (@results);

        $self->linked_works ($c, $opts, $opts->{works}->{items});
    }

    $self->_tags_and_ratings($c, 'Artist', $artist, $opts);

    if ($c->stash->{inc}->has_rels)
    {
        my $types = $c->stash->{inc}->get_rel_types();
        my @rels = $c->model('Relationship')->load_subset($types, $artist);
    }

    $c->res->content_type($c->stash->{serializer}->mime_type . '; charset=utf-8');
    $c->res->body($c->stash->{serializer}->serialize('artist', $artist, $c->stash->{inc}, $opts));
}

sub artist_search : Chained('root') PathPart('artist') Args(0)
{
    my ($self, $c) = @_;

    if ($c->stash->{linked})
    {
        warn "FIXME: YAY A BROWSE REQUEST. PLZ IMPLEMENT\n";
        $c->stash->{error} = '';
        $c->detach('bad_req');
    }

    my $result = xml_search('artist', $c->stash->{args});
    $c->res->content_type($c->stash->{serializer}->mime_type . '; charset=utf-8');
    if (exists $result->{xml})
    {
        $c->res->body($result->{xml});
    }
    else
    {
        $c->res->status($result->{code});
        $c->res->body($c->stash->{serializer}->output_error($result->{error}));
    }
}

sub release_group : Chained('root') PathPart('release-group') Args(1)
{
    my ($self, $c, $gid) = @_;

    if (!MusicBrainz::Server::Validation::IsGUID($gid))
    {
        $c->stash->{error} = "Invalid mbid.";
        $c->detach('bad_req');
    }

    my $rg = $c->model('ReleaseGroup')->get_by_gid($gid);
    unless ($rg) {
        $c->detach('not_found');
    }

    my $opts = {};
    $self->linked_release_groups ($c, $opts, [ $rg ]);

    if ($c->stash->{inc}->releases)
    {
        my @results = $c->model('Release')->find_by_release_group($rg->id, $MAX_ITEMS);
        $opts->{releases} = $self->make_list (@results);

        $self->linked_releases ($c, $opts, $opts->{releases}->{items});
    }

    if ($c->stash->{inc}->artists)
    {
        $c->model('ArtistCredit')->load($rg);

        my @artists = map { $c->model('Artist')->load ($_); $_->artist } @{ $rg->artist_credit->names };

        $self->linked_artists ($c, $opts, \@artists);
    }


    $self->_tags_and_ratings($c, 'ReleaseGroup', $rg, $opts);
    if ($c->stash->{inc}->has_rels)
    {
        my $types = $c->stash->{inc}->get_rel_types();
        my @rels = $c->model('Relationship')->load_subset($types, $rg);
    }

    $c->res->content_type($c->stash->{serializer}->mime_type . '; charset=utf-8');
    $c->res->body($c->stash->{serializer}->serialize('release-group', $rg, $c->stash->{inc}, $opts));
}

sub release_group_search : Chained('root') PathPart('release-group') Args(0)
{
    my ($self, $c) = @_;

    if ($c->stash->{linked})
    {
        warn "FIXME: YAY A BROWSE REQUEST. PLZ IMPLEMENT\n";
        $c->stash->{error} = '';
        $c->detach('bad_req');
    }

    my $result = xml_search('release-group', $c->stash->{args});
    $c->res->content_type($c->stash->{serializer}->mime_type . '; charset=utf-8');
    if (exists $result->{xml})
    {
        $c->res->body($result->{xml});
    }
    else
    {
        $c->res->status($result->{code});
        $c->res->body($c->stash->{serializer}->output_error($result->{error}));
    }
}

sub release_toplevel
{
    my ($self, $c, $opts, $release) = @_;

    $c->model('Release')->load_meta($release);
    $self->linked_releases ($c, $opts, [ $release ]);

    if ($c->stash->{inc}->artists)
    {
        $c->model('ArtistCredit')->load($release);

        my @artists = map { $c->model('Artist')->load ($_); $_->artist } @{ $release->artist_credit->names };

        $self->linked_artists ($c, $opts, \@artists);
    }

    if ($c->stash->{inc}->labels)
    {
        $c->model('ReleaseLabel')->load($release);
        $c->model('Label')->load($release->all_labels);

        $self->linked_labels ($c, $opts, $release->all_labels);
    }

    if ($c->stash->{inc}->release_groups)
    {
         $c->model('ReleaseGroup')->load($release);
         $c->model('ReleaseGroupType')->load($release->release_group);
    }

    if ($c->stash->{inc}->recordings)
    {
        my @mediums;
        if (!$c->stash->{inc}->media)
        {
            $c->model('Medium')->load_for_releases($release);
        }

        @mediums = $release->all_mediums;

        my @tracklists = grep { defined } map { $_->tracklist } @mediums;
        $c->model('Track')->load_for_tracklists(@tracklists);

        my @recordings = $c->model('Recording')->load(map { $_->all_tracks } @tracklists);
        $c->model('Recording')->load_meta(@recordings);

        $self->linked_recordings ($c, $opts, \@recordings);
    }

    if ($c->stash->{inc}->has_rels)
    {
        my $types = $c->stash->{inc}->get_rel_types();
        my @rels = $c->model('Relationship')->load_subset($types, $release);
    }
}

sub release: Chained('root') PathPart('release') Args(1)
{
    my ($self, $c, $gid) = @_;

    if (!MusicBrainz::Server::Validation::IsGUID($gid))
    {
        $c->stash->{error} = "Invalid mbid.";
        $c->detach('bad_req');
    }

    my $release = $c->model('Release')->get_by_gid($gid);
    unless ($release) {
        $c->detach('not_found');
    }

    my $opts = {};
    $self->release_toplevel ($c, $opts, $release);

    $c->res->content_type($c->stash->{serializer}->mime_type . '; charset=utf-8');
    $c->res->body($c->stash->{serializer}->serialize('release', $release, $c->stash->{inc}, $opts));
}

sub release_search : Chained('root') PathPart('release') Args(0)
{
    my ($self, $c) = @_;

    if ($c->stash->{linked})
    {
        warn "FIXME: YAY A BROWSE REQUEST. PLZ IMPLEMENT\n";
        $c->stash->{error} = '';
        $c->detach('bad_req');
    }

    my $result = xml_search('release', $c->stash->{args});
    $c->res->content_type($c->stash->{serializer}->mime_type . '; charset=utf-8');
    if (exists $result->{xml})
    {
        $c->res->body($result->{xml});
    }
    else
    {
        $c->res->status($result->{code});
        $c->res->body($c->stash->{serializer}->output_error($result->{error}));
    }
}

sub recording_toplevel
{
    my ($self, $c, $opts, $recording) = @_;

    $self->linked_recordings ($c, $opts, [ $recording ]);

    if ($c->stash->{inc}->releases)
    {
        my @results = $c->model('Release')->find_by_recording($recording->id, $MAX_ITEMS);
        $self->linked_releases ($c, $opts, $results[0]);
        $opts->{releases}->{$recording->id} = $self->make_list (@results);
    }

    if ($c->stash->{inc}->artists)
    {
        $c->model('ArtistCredit')->load($recording);

        my @artists = map { $c->model('Artist')->load ($_); $_->artist } @{ $recording->artist_credit->names };

        $self->linked_artists ($c, $opts, \@artists);
    }

    $self->_tags_and_ratings($c, 'Recording', $recording, $opts);

    if ($c->stash->{inc}->has_rels)
    {
        my $types = $c->stash->{inc}->get_rel_types();
        my @rels = $c->model('Relationship')->load_subset($types, $recording);
    }
}

sub recording: Chained('root') PathPart('recording') Args(1)
{
    my ($self, $c, $gid) = @_;

    if (!MusicBrainz::Server::Validation::IsGUID($gid))
    {
        $c->stash->{error} = "Invalid mbid.";
        $c->detach('bad_req');
    }

    my $recording = $c->model('Recording')->get_by_gid($gid);
    unless ($recording) {
        $c->detach('not_found');
    }

    my $opts = {};
    $self->recording_toplevel ($c, $opts, $recording);

    $c->res->content_type($c->stash->{serializer}->mime_type . '; charset=utf-8');
    $c->res->body($c->stash->{serializer}->serialize('recording', $recording, $c->stash->{inc}, $opts));
}

sub recording_browse : Private
{
    my ($self, $c) = @_;

    my ($resource, $id) = @{ $c->stash->{linked} };
    my ($limit, $offset) = $self->_limit_and_offset ($c);

    if (!MusicBrainz::Server::Validation::IsGUID($id))
    {
        $c->stash->{error} = "Invalid mbid.";
        $c->detach('bad_req');
    }

    my $recordings;
    my $total;
    if ($resource eq 'artist')
    {
        my $artist = $c->model('Artist')->get_by_gid($id);
        unless ($artist) {
            $c->detach('not_found');
        }

        my @tmp = $c->model('Recording')->find_by_artist ($artist->id, $limit, $offset);
        $recordings = $self->make_list (@tmp, $offset);
    }

    my $opts;
    for (@{ $recordings->{items} })
    {
        $self->recording_toplevel ($c, $opts, $_);
    }

    $c->res->content_type($c->stash->{serializer}->mime_type . '; charset=utf-8');
    $c->res->body($c->stash->{serializer}->serialize('recording-list', $recordings, $c->stash->{inc}, $opts));
}



sub recording_search : Chained('root') PathPart('recording') Args(0)
{
    my ($self, $c) = @_;

    $c->detach('recording_browse') if ($c->stash->{linked});

    my $result = xml_search('recording', $c->stash->{args});
    $c->res->content_type($c->stash->{serializer}->mime_type . '; charset=utf-8');
    if (exists $result->{xml})
    {
        $c->res->body($result->{xml});
    }
    else
    {
        $c->res->status($result->{code});
        $c->res->body($c->stash->{serializer}->output_error($result->{error}));
    }
}

sub label : Chained('root') PathPart('label') Args(1)
{
    my ($self, $c, $gid) = @_;

    if (!$gid || !MusicBrainz::Server::Validation::IsGUID($gid))
    {
        $c->stash->{error} = "Invalid mbid.";
        $c->detach('bad_req');
    }

    my $label = $c->model('Label')->get_by_gid($gid);
    unless ($label) {
        $c->detach('not_found');
    }

    my $opts = {};
    $self->linked_labels ($c, $opts, [ $label ]);

    $c->model('LabelType')->load($label);
    $c->model('Country')->load($label);

    if ($c->stash->{inc}->aliases)
    {
        $opts->{aliases} = $c->model('Label')->alias->find_by_entity_id($label->id);
    }

    if ($c->stash->{inc}->releases)
    {
        my @results = $c->model('Release')->find_by_label($label->id, $MAX_ITEMS);
        $opts->{releases} = $self->make_list (@results);

        $self->linked_releases ($c, $opts, $opts->{releases}->{items});
    }

    $self->_tags_and_ratings($c, 'Label', $label, $opts);

    if ($c->stash->{inc}->has_rels)
    {
        my $types = $c->stash->{inc}->get_rel_types();
        my @rels = $c->model('Relationship')->load_subset($types, $label);
    }

    $c->res->content_type($c->stash->{serializer}->mime_type . '; charset=utf-8');
    $c->res->body($c->stash->{serializer}->serialize('label', $label, $c->stash->{inc}, $opts));
}

sub label_search : Chained('root') PathPart('label') Args(0)
{
    my ($self, $c) = @_;

    if ($c->stash->{linked})
    {
        warn "FIXME: YAY A BROWSE REQUEST. PLZ IMPLEMENT\n";
        $c->stash->{error} = '';
        $c->detach('bad_req');
    }

    my $result = xml_search('label', $c->stash->{args});
    $c->res->content_type($c->stash->{serializer}->mime_type . '; charset=utf-8');
    if (exists $result->{xml})
    {
        $c->res->body($result->{xml});
    }
    else
    {
        $c->res->status($result->{code});
        $c->res->body($c->stash->{serializer}->output_error($result->{error}));
    }
}


sub work_toplevel
{
    my ($self, $c, $opts, $work) = @_;

    if ($c->stash->{inc}->artists)
    {
        $c->model('ArtistCredit')->load($work);

        my @artists = map { $c->model('Artist')->load ($_); $_->artist } @{ $work->artist_credit->names };

        $self->linked_artists ($c, $opts, \@artists);
    }

    $self->_tags_and_ratings($c, 'Work', $work, $opts);

    if ($c->stash->{inc}->has_rels)
    {
        my $types = $c->stash->{inc}->get_rel_types();
        my @rels = $c->model('Relationship')->load_subset($types, $work);
    }

    $c->model('WorkType')->load($work);
}

sub work : Chained('root') PathPart('work') Args(1)
{
    my ($self, $c, $gid) = @_;

    if (!MusicBrainz::Server::Validation::IsGUID($gid))
    {
        $c->stash->{error} = "Invalid mbid.";
        $c->detach('bad_req');
    }

    my $work = $c->model('Work')->get_by_gid($gid);
    unless ($work) {
        $c->detach('not_found');
    }

    my $opts = {};
    $self->work_toplevel ($c, $opts, $work);

    $c->res->content_type($c->stash->{serializer}->mime_type . '; charset=utf-8');
    $c->res->body($c->stash->{serializer}->serialize('work', $work, $c->stash->{inc}, $opts));
}

sub work_search : Chained('root') PathPart('work') Args(0)
{
    my ($self, $c) = @_;

    if ($c->stash->{linked})
    {
        warn "FIXME: YAY A BROWSE REQUEST. PLZ IMPLEMENT\n";
        $c->stash->{error} = '';
        $c->detach('bad_req');
    }

    my $result = xml_search('work', $c->stash->{args});
    $c->res->content_type($c->stash->{serializer}->mime_type . '; charset=utf-8');
    if (exists $result->{xml})
    {
        $c->res->body($result->{xml});
    }
    else
    {
        $c->res->status($result->{code});
        $c->res->body($c->stash->{serializer}->output_error($result->{error}));
    }
}

sub puid : Chained('root') PathPart('puid') Args(1)
{
    my ($self, $c, $id) = @_;

    if (!MusicBrainz::Server::Validation::IsGUID($id))
    {
        $c->stash->{error} = "Invalid puid.";
        $c->detach('bad_req');
    }

    my $puid = $c->model('PUID')->get_by_puid($id);
    unless ($puid) {
        $c->detach('not_found');
    }

    my $opts;
    my @recording_puids = $c->model('RecordingPUID')->find_by_puid($puid->id);
    my @recordings = map { $_->recording } @recording_puids;
    $opts->{recordings} = $self->make_list (\@recordings);

    for (@recordings)
    {
        $self->recording_toplevel ($c, $opts, $_);
    }

    $c->res->content_type($c->stash->{serializer}->mime_type . '; charset=utf-8');
    $c->res->body($c->stash->{serializer}->serialize('puid', $puid, $c->stash->{inc}, $opts));
}

sub isrc : Chained('root') PathPart('isrc') Args(1)
{
    my ($self, $c, $isrc) = @_;

    if (!is_valid_isrc($isrc))
    {
        $c->stash->{error} = "Invalid isrc.";
        $c->detach('bad_req');
    }

    my @isrcs = $c->model('ISRC')->find_by_isrc($isrc);
    unless (@isrcs) {
        $c->detach('not_found');
    }

    my $opts;
    my @recordings = $c->model('Recording')->load(@isrcs);
    $opts->{recordings} = $self->make_list (\@recordings);

    for (@recordings)
    {
        $self->recording_toplevel ($c, $opts, $_);
    }

    $c->res->content_type($c->stash->{serializer}->mime_type . '; charset=utf-8');
    $c->res->body($c->stash->{serializer}->serialize('isrc', \@isrcs, $c->stash->{inc}, $opts));
}

sub discid : Chained('root') PathPart('discid') Args(1)
{
    my ($self, $c, $id) = @_;

    if (!is_valid_discid($id))
    {
        $c->stash->{error} = "Invalid discid.";
        $c->detach('bad_req');
    }

    my $cdtoc = $c->model('CDTOC')->get_by_discid($id);
    unless ($cdtoc) {
        $c->detach('not_found');
    }

    my @mediumcdtocs = $c->model('MediumCDTOC')->find_by_cdtoc($cdtoc->id);
    $c->model('Medium')->load(@mediumcdtocs);

    my $opts = {};
    my @releases = $c->model('Release')->find_by_medium([ map { $_->medium_id } @mediumcdtocs ]);
    $opts->{releases} = $self->make_list (\@releases);

    for (@releases)
    {
        $self->release_toplevel ($c, $opts, $_);
    }

    $c->res->content_type($c->stash->{serializer}->mime_type . '; charset=utf-8');
    $c->res->body($c->stash->{serializer}->serialize('discid', $cdtoc, $c->stash->{inc}, $opts));
}

sub iswc : Chained('root') PathPart('iswc') Args(1)
{
    my ($self, $c, $iswc) = @_;

    if (!is_valid_iswc($iswc))
    {
        $c->stash->{error} = "Invalid iswc.";
        $c->detach('bad_req');
    }

    my @works = $c->model('Work')->find_by_iswc($iswc);
    unless (@works) {
        $c->detach('not_found');
    }

    my $opts;
    $opts->{works} = $self->make_list (\@works);

    for (@works)
    {
        $self->work_toplevel ($c, $opts, $_);
    }

    $c->res->content_type($c->stash->{serializer}->mime_type . '; charset=utf-8');
    $c->res->body($c->stash->{serializer}->serialize('isrc', \@works, $c->stash->{inc}, $opts));
}

sub default : Path
{
    my ($self, $c, $resource) = @_;

    $c->stash->{serializer} = $serializers{$self->get_default_serialization_type}->new();
    $c->stash->{error} = "Invalid resource: $resource. ";
    $c->detach('bad_req');
}

no Moose;
1;

=head1 COPYRIGHT

Copyright (C) 2010 MetaBrainz Foundation
Copyright (C) 2009 Lukas Lalinsky
Copyright (C) 2009 Robert Kaye

This program is free software; you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation; either version 2 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program; if not, write to the Free Software
Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.

=cut
