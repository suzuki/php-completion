use strict;
use warnings;
use utf8;

use List::MoreUtils qw(uniq);
use Web::Scraper;
use URI;

my $functions = scraper {
    process "a.index", 'functions[]' => sub {
        my $text = $_->as_text or return;
	if ($text =~ /[^A-Za-z0-9_:\-\/\\]/) {
	    return;
	}

        return $text;
    };
    result 'functions';
}->scrape(URI->new('http://jp.php.net/manual/ja/indexes.functions.php'));

map {
    s/\(\)$//;
    s/.*->(.*)$/$1/;
    s/.*::(.*)$/$1/;
} @$functions;

print join "\n", uniq sort @$functions;
