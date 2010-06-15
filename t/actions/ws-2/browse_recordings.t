use utf8;
use strict;
use Test::More;
use XML::SemanticDiff;
use Catalyst::Test 'MusicBrainz::Server';
use MusicBrainz::Server::Test qw( xml_ok v2_schema_validator );
use Test::WWW::Mechanize::Catalyst;

my $c = MusicBrainz::Server::Test->create_test_context;
my $v2 = v2_schema_validator;
my $mech = Test::WWW::Mechanize::Catalyst->new(catalyst_app => 'MusicBrainz::Server');
my $diff = XML::SemanticDiff->new;

$mech->get_ok('/ws/2/recording?artist=3088b672-fba9-4b4b-8ae0-dce13babfbb4&inc=puids&limit=3', 'browse recordings, inc=puids (first page)');
&$v2 ($mech->content, "Validate browse recordings, inc=puids (first page)");

my $expected = '<?xml version="1.0" encoding="UTF-8"?>
<metadata xmlns="http://musicbrainz.org/ns/mmd-2.0#">
    <recording-list count="10">
        <recording id="7e379a1d-f2bc-47b8-964e-00723df34c8a">
            <title>Be Rude to Your School</title><length>208706</length>
        </recording>
        <recording id="6f9c8c32-3aae-4dad-b023-56389361cf6b">
            <title>Bibi Plone</title><length>173960</length>
        </recording>
        <recording id="4f392ffb-d3df-4f8a-ba74-fdecbb1be877">
            <title>Busy Working</title><length>217440</length>
        </recording>
    </recording-list>
</metadata>';

is ($diff->compare ($mech->content, $expected), 0, 'result ok');

$mech->get_ok('/ws/2/recording?artist=3088b672-fba9-4b4b-8ae0-dce13babfbb4&inc=puids&limit=3&offset=3', 'browse recordings, inc=puids (second page)');
&$v2 ($mech->content, "Validate browse recordings, inc=puids (second page)");

$expected = '<?xml version="1.0" encoding="UTF-8"?>
<metadata xmlns="http://musicbrainz.org/ns/mmd-2.0#">
    <recording-list count="10" offset="3">
        <recording id="791d9b27-ae1a-4295-8943-ded4284f2122">
            <title>Marbles</title><length>229826</length>
        </recording>
        <recording id="44704dda-b877-4551-a2a8-c1f764476e65">
            <title>On My Bus</title><length>267560</length>
        </recording>
        <recording id="6e89c516-b0b6-4735-a758-38e31855dcb6">
            <title>Plock</title><length>237133</length>
        </recording>
    </recording-list>
</metadata>';

is ($diff->compare ($mech->content, $expected), 0, 'result ok');

done_testing;
