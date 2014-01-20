#!/usr/bin/perl
use LWP;
use HTTP::Request::Common;
use LWP::UserAgent;
use JSON;

print "Content-type: text/html\n\n";

#read form data
read (STDIN, $InData, $ENV{'CONTENT_LENGTH'});
@array = split(/&/, $InData);
@array[0] =~ s/name=//g;
@array[1] =~ s/hosts=//g;

#make json (slice)
my $json = '{"id":"@array[0]","description":"@array[0]"}';

#post json (slice)
my $uri = 'http://127.0.0.1:8888/networks';
my $req = HTTP::Request->new( 'POST', $uri );
$req->header( 'Content-Type' => 'application/json' );
$req->content( $json );

my $ua = LWP::UserAgent->new;
$ua->request( $req );

#get hosts

#make json (hosts)
my $json = '{"id":"","mac":""}';

#post json (hosts)
my $uri = 'http://127.0.0.1:8888/hosts';
my $req = HTTP::Request->new( 'POST', $uri );
$req->header( 'Content-Type' => 'application/json' );
$req->content( $json );

my $ua = LWP::UserAgent->new;
$ua->request( $req );

#print information
print <<"EOF";
<html>
<head>
<title> </title>
</head>
<body>
@array[0]
@array[1]
</body>
</html>
EOF

