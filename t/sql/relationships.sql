SET client_min_messages TO 'warning';

INSERT INTO link_attribute_type (id, root, gid, name)
    VALUES (1, 1, '36990974-4f29-4ea1-b562-3838fa9b8832', 'Additional'),
           (2, 2, '108d76bd-95eb-4099-aed6-447e4ec78553', 'instrument');

INSERT INTO link_attribute_type (id, parent, root, gid, name)
    VALUES (3, 2, 2, '4f7bb10f-396c-466a-8221-8e93f5e454f9', 'string instruments'),
           (4, 3, 2, 'c3273296-91ba-453d-94e4-2fb6e958568e', 'guitar'),
           (779, NULL, 779, 'a59c5830-5ec7-38fe-9a21-c7ea54f6650a', 'number');

INSERT INTO link_text_attribute_type (attribute_type) VALUES (779);
INSERT INTO link_creditable_attribute_type (attribute_type) VALUES (3), (4);

INSERT INTO link_type_attribute_type (link_type, attribute_type, min, max)
    VALUES (148, 1, 0, 1),
           (148, 2, 1, NULL),
           (743, 779, 0, 0);

INSERT INTO link (id, link_type, attribute_count) VALUES (1, 148, 1),
                                                         (2, 148, 2),
                                                         (3, 743, 1),
                                                         (4, 148, 1);

INSERT INTO link_attribute (link, attribute_type) VALUES (1, 4),
                                                         (2, 1),
                                                         (2, 3),
                                                         (3, 779),
                                                         (4, 4);

INSERT INTO link_attribute_text_value (link, attribute_type, text_value)
    VALUES (3, 779, 'oh look a number');

INSERT INTO link_attribute_credit (link, attribute_type, credited_as)
    VALUES (4, 4, 'crazy guitar');

INSERT INTO artist (id, gid, name, sort_name)
    VALUES (1, 'e2a083a9-9942-4d6e-b4d2-8397320b95f7', 'Artist 1', 'Artist 1'),
           (2, '2fed031c-0e89-406e-b9f0-3d192637907a', 'Artist 2', 'Artist 2');

INSERT INTO artist_credit (id, name, artist_count) VALUES (1, 'Artist 1', 1);
INSERT INTO artist_credit_name (artist_credit, position, artist, name, join_phrase)
    VALUES (1, 0, 1, 'Artist 1', '');

INSERT INTO recording (id, gid, name, artist_credit)
    VALUES (1, '99caac80-72e4-11de-8a39-0800200c9a66', 'Track 1', 1),
           (2, 'a12bb640-72e4-11de-8a39-0800200c9a66', 'Track 2', 1);

INSERT INTO l_artist_recording (id, link, entity0, entity1) VALUES (1, 1, 1, 1);
INSERT INTO l_artist_recording (id, link, entity0, entity1, edits_pending) VALUES (2, 1, 2, 1, 1);
INSERT INTO l_artist_recording (id, link, entity0, entity1) VALUES (3, 2, 1, 2);
