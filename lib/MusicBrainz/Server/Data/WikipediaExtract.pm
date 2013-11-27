package MusicBrainz::Server::Data::WikipediaExtract;
use Moose;
use namespace::autoclean;

use Readonly;
use aliased 'MusicBrainz::Server::Entity::WikipediaExtract';
use JSON;
use Encode qw( encode );
use URI::Escape qw( uri_escape_utf8 );
use List::Util qw( first );

with 'MusicBrainz::Server::Data::Role::Context';
with 'MusicBrainz::Server::Data::Role::MediaWikiAPI';

# We'll assume interlanguage links don't change much
Readonly my $LANG_CACHE_TIMEOUT => 60 * 60 * 24 * 7; # 1 week
# Extracts will change more often, but
# we still want to keep them around a while
Readonly my $EXTRACT_CACHE_TIMEOUT => 60 * 60 * 24 * 3; # 3 days

sub get_extract
{
    my ($self, $link, $wanted_language, %opts) = @_;
    my $cache_only = $opts{cache_only} // 0;

    if ($link->isa('MusicBrainz::Server::Entity::URL::Wikipedia') && $wanted_language eq $link->language) {
        return $self->get_extract_by_language($link->page_name, $link->language, cache_only => $cache_only);
    }

    # We didn't by luck get a link in the right language
    my $languages = $self->get_available_languages($link, cache_only => $cache_only);

    if (defined $languages && scalar @$languages) {
        my $lang_wanted = first { $_->{lang} eq $wanted_language } @$languages;
        # Make sure if english was the link language, we still know to use it
        my $english = $link->isa('MusicBrainz::Server::Entity::URL::Wikipedia') && $link->language eq 'en' ?
                          {'title' => $link->page_name, 'lang' => 'en'} :
                          first { $_->{lang} eq 'en' } @$languages;

        # Desired language, fallback to english, fall back to "whatever we have"
        my $lang_to_use = $lang_wanted || $english ||
            ($link->isa('MusicBrainz::Server::Entity::URL::Wikipedia') ?
             {'title' => $link->page_name, 'lang' => $link->language} :
             $languages->[0]);
        return $self->get_extract_by_language($lang_to_use->{title}, $lang_to_use->{lang}, cache_only => $cache_only);
    } else {
        # We have no language data, probably because we requested cache_only
        return undef;
    }
}

sub get_extract_by_language
{
    my ($self, $title, $language, %opts) = @_;
    my $url_pattern = "http://%s.wikipedia.org/w/api.php?action=query&prop=extracts&exintro=1&format=json&redirects=1&titles=%s";
    return $self->_fetch_cache_or_url($url_pattern, 'extract',
                                      $EXTRACT_CACHE_TIMEOUT,
                                      $title, $language,
                                      \&_extract_by_language_callback,
                                      %opts);
}

sub get_available_languages
{
    my ($self, $link, %opts) = @_;
    my ($url_pattern, $key, $callback, $language);
    if ($link->isa('MusicBrainz::Server::Entity::URL::Wikidata')) {
        $url_pattern = "http://www.wikidata.org/w/api.php?action=wbgetentities&format=json&props=sitelinks&ids=%s%s";
        $key = 'sitelinks';
        $callback = \&_wikidata_languages_callback;
    } else {
        $url_pattern = "http://%s.wikipedia.org/w/api.php?action=query&prop=langlinks&lllimit=500&format=json&redirects=1&titles=%s";
        $key = 'langlinks';
        $callback = \&_wikipedia_languages_callback;
        $language = $link->language;
    }
    return $self->_fetch_cache_or_url($url_pattern, $key,
                                      $LANG_CACHE_TIMEOUT,
                                      $link->page_name, $language,
                                      $callback,
                                      %opts);
}

sub _wikidata_languages_callback
{
    my (%opts) = @_;
    if ($opts{fetched}{content}{sitelinks}) {
        my @langs;
        for my $wiki (keys %{ $opts{fetched}{content}{sitelinks} }) {
            if ($wiki =~ /wiki$/) {
                my $lang = $wiki;
                $lang =~ s/wiki$//;
                my $page = $opts{fetched}{content}{sitelinks}{$wiki}{title};
                push @langs, {"lang" => $lang, "title" => $page}
            }
        }
        return \@langs;
    }
}

sub _wikipedia_languages_callback
{
    my (%opts) = @_;
    my @langs = map { {"lang" => $_->{lang}, "title" => $_->{"*"}} } @{ $opts{fetched}{content} };
    return \@langs;
}

sub _extract_by_language_callback
{
    my (%opts) = @_;
    if ($opts{fetched}{content}) {
        return WikipediaExtract->new( title => $opts{fetched}{title},
                                      content => $opts{fetched}{content},
                                      canonical => $opts{fetched}{canonical},
                                      language => $opts{language} );
    }
}

__PACKAGE__->meta->make_immutable;
no Moose;
1;

=head1 COPYRIGHT

Copyright (C) 2012 Ian McEwen
Copyright (C) 2012 MetaBrainz Foundation

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
