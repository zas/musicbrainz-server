package t::MusicBrainz::Server::Data::Link;
use Test::Routine;
use Test::Moose;
use Test::More;

use MusicBrainz::Server::Data::Link;

use MusicBrainz::Server::Test;

with 't::Context';

test all => sub {

my $test = shift;
MusicBrainz::Server::Test->prepare_test_database($test->c, '+relationships');

my $link_id = $test->c->model('Link')->find_or_insert({
    link_type_id => 148,
    ended => 0,
    attributes => [{ type => { id => 4 } }],
});
is($link_id, 1);

$link_id = $test->c->model('Link')->find_or_insert({
    link_type_id => 148,
    ended => 0,
    attributes => [ map +{ type => { id => $_ } }, (1, 3) ],
});
is($link_id, 2);

$link_id = $test->c->model('Link')->find_or_insert({
    link_type_id => 148,
    ended => 0,
    attributes => [ map +{ type => { id => $_ } }, ( 3, 1 ) ],
});
is($link_id, 2);

$test->c->sql->begin;
$link_id = $test->c->model('Link')->find_or_insert({
    link_type_id => 148,
    begin_date => { year => 2009 },
    end_date => { year => 2010 },
    ended => 0,
    attributes => [ map +{ type => { id => $_ } }, (1, 3) ],
});
$test->c->sql->commit;
is($link_id, 5);

my $link = $test->c->model('Link')->get_by_id(5);
is_deeply($link->begin_date, { year => 2009 });
is_deeply($link->end_date, { year => 2010 });

$test->c->sql->begin;
$link_id = $test->c->model('Link')->find_or_insert({
    link_type_id => 148,
    begin_date => { year => 2009 },
    end_date => { year => 2010 },
    ended => 0,
    attributes => [ map +{ type => { id => $_ } }, (1, 3) ],
});
$test->c->sql->commit;
is($link_id, 5, "find_or_insert() correctly re-uses a link with end date");

$test->c->sql->begin;
$link_id = $test->c->model('Link')->find_or_insert({
    link_type_id => 743,
    attributes => [{ type => { id => 779 }, text_value => 'oh look a number' }],
});
$test->c->sql->commit;
is($link_id, 3, "find_or_insert() correctly re-uses a link with a text value");

$test->c->sql->begin;
$link_id = $test->c->model('Link')->find_or_insert({
    link_type_id => 148,
    attributes => [{ type => { id => 4 }, credited_as => 'crazy guitar' }],
});
$test->c->sql->commit;
is($link_id, 4, "find_or_insert() correctly re-uses a link with an attribute credit");

};

1;
