#!/usr/bin/perl
use Data::Dumper;
use LWP;
use HTTP::Request::Common;
use LWP::UserAgent;
use JSON;

print "Content-type: text/html\n\n";

#read form data
read (STDIN, $InData, $ENV{'CONTENT_LENGTH'});
my @array = split(/&/, $InData);
$array[0] =~ s/slice_name=//g;
$array[1] =~ s/number_of_hosts=//g;

# 未使用ホスト数を確認
# 必要個数分だけ未使用ホストの MAC を取得
my @array_new_hosts_mac = ();
my $get_new_hosts_mac_uri = 'http://127.0.0.1:8888/hosts/available/num/'.$array[1];
my $get_new_hosts_mac_req = HTTP::Request->new( 'GET', $get_new_hosts_mac_uri );

my $get_new_hosts_mac_ua = LWP::UserAgent->new;
my $get_new_hosts_mac_response = $get_new_hosts_mac_ua->request( $get_new_hosts_mac_req );

if ($get_new_hosts_mac_response->is_success) {
    print "[Status]: ", $get_new_hosts_mac_response->status_line, "\n";
    print "[Content]:\n", $get_new_hosts_mac_response->content, "\n";
} else {
    print $get_new_hosts_mac_response->status_line, "\n";
}
my @array_new_hosts_mac = decode_json($get_new_hosts_mac_response->content);
print $array_new_hosts_mac[0], "\n";

# スライス作成
my $make_new_slice_json = '{"id":"'.$array[0].'","description":"'.$array[0].'"}';
my $make_new_slice_uri = 'http://127.0.0.1:8888/networks';
my $make_new_slice_req = HTTP::Request->new( 'POST', $make_new_slice_uri );
$make_new_slice_req->header( 'Content-Type' => 'application/json' );
$make_new_slice_req->content( $make_new_slice_json );

my $make_new_slice_ua = LWP::UserAgent->new;
$make_new_slice_ua->request( $make_new_slice_req );



# 作成したスライスにホスト追加

# 追加したホストの使用状態を"使用中"に変更




# #make json (slice)
# my $json = '{"id":"@array[0]","description":"@array[0]"}';

# #post json (slice)
# my $uri = 'http://127.0.0.1:8888/networks';
# my $req = HTTP::Request->new( 'POST', $uri );
# $req->header( 'Content-Type' => 'application/json' );
# $req->content( $json );

# my $ua = LWP::UserAgent->new;
# $ua->request( $req );

# #get hosts

# #make json (hosts)
# my $json = '{"id":"","mac":""}';

# #post json (hosts)
# my $uri = 'http://127.0.0.1:8888/hosts';
# my $req = HTTP::Request->new( 'POST', $uri );
# $req->header( 'Content-Type' => 'application/json' );
# $req->content( $json );

# my $ua = LWP::UserAgent->new;
# $ua->request( $req );

#print information
print <<"EOF";
<!DOCTYPE html>
<html>
<head>
<title> result </title>
</head>
<body>
$array[0]
$array[1]
</body>
</html>
EOF

