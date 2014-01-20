#!/usr/bin/perl
use strict;
use CGI;
use LWP;
use LWP::UserAgent;
use HTTP::Request::Common;
use JSON;


my $q = new CGI;
my $slice_name ='initial_slice_name';
my $number_of_hosts = 0;
my @array_new_hosts_mac = ();
my @array_new_hosts_mac_str = ();

print "Content-type: text/html; charset=UTF-8\n\n";

&main();
exit;

sub main(){
    &read_form_data();
    &check_available_hosts();
    &create_new_slice();
    &add_hosts_to_new_slice();
    &update_added_hosts();
    &print_message_success();
}


# フォームのデータを取得
sub read_form_data(){
    # Read form data
    $slice_name = $q->param('slice_name') || undef;
    chomp($slice_name);
    $number_of_hosts = $q->param('number_of_hosts') || undef;
    chomp($number_of_hosts);
}


# 未使用ホスト数を確認
# 必要個数分だけ未使用ホストの MAC を取得
sub check_available_hosts(){
    my @array_new_hosts_mac = ();

    my $uri = 'http://127.0.0.1:8888/hosts/available/num/'.$number_of_hosts;
    my $req = HTTP::Request->new( 'GET', $uri );
    
    my $ua = LWP::UserAgent->new;
    my $response = $ua->request( $req );
    
    if($response->is_success){
	@array_new_hosts_mac = @{decode_json($response->content)};
	my $m_str = '';
	foreach my $m (@array_new_hosts_mac){
	    $m_str = &int_to_mac_string($m);
	    push(@array_new_hosts_mac_str, $m_str);
	}
    }
    else{
	&print_message_error((caller 0)[3], $response->status_line)
    }
}


# スライス作成
sub create_new_slice(){
    my $json = '{"id":"'.$slice_name.'","description":"'.$slice_name.'"}';
    my $uri = 'http://127.0.0.1:8888/networks';
    my $req = HTTP::Request->new( 'POST', $uri );
    $req->header( 'Content-Type' => 'application/json' );
    $req->content( $json );
    
    my $ua = LWP::UserAgent->new;
    my $response = $ua->request( $req );
    
    if($response->is_success){}
    else{
	&print_message_error((caller 0)[3], $response->status_line)
    }
}

# 作成したスライスにホスト追加
sub add_hosts_to_new_slice(){
    my $num = @array_new_hosts_mac_str;
    print ">>", $num, "\n";
    foreach my $m_str (@array_new_hosts_mac_str){
	my $uri = 'http://127.0.0.1:8888/networks/'.$slice_name.'/attachments';
	print $uri, "\n";
	my $req = HTTP::Request->new( 'POST', $uri );
	$req->header( 'Content-Type' => 'application/json' );
    
	my $ua = LWP::UserAgent->new;
	my $json = '{"id":"'.$m_str.'", "mac":"'.$m_str.'"}';
	print $json, "\n";
	$req->content( $json );
	my $response = $ua->request( $req );

	if($response->is_success){}
	else{
	    &print_message_error((caller 0)[3], $response->status_line)
	}
    }
}


# 追加したホストの使用状態を"使用中"に変更
sub update_added_hosts(){
    foreach my $m_str (@array_new_hosts_mac_str){
	$m_str =~ s/://g;
	print $m_str, "\n";
	my $uri = 'http://127.0.0.1:8888/hosts/mac/'.$m_str;
	print $uri, "\n";
	my $req = HTTP::Request->new( 'PUT', $uri );
	$req->header( 'Content-Type' => 'application/json' );
	 
	my $ua = LWP::UserAgent->new;
	my $json = '{ "is_occupied": "1" }';
	$req->content( $json );
	my $response = $ua->request( $req );

	if($response->is_success){}
	else{
	    &print_message_error((caller 0)[3], $response->status_line)
	}
    }
}


# Print information
sub print_message_success(){
# print "Content-type: text/html; charset=UTF-8\n\n";
print <<"EOF";
<!DOCTYPE html>
<html>
<head>
<title> SVNM: 仮想ネットワーク作成結果 </title>
</head>
<body>
<h1>仮想ネットワーク作成結果</h1>
<p style="color: blue;"><b>正常に仮想ネットワークが作成されました。</b></p>
<ul>
<li>仮想ネットワーク名: $slice_name</li>
<li>ホスト数: $number_of_hosts</li>
</ul>
<p><a href="../html/index.html">メニューへ戻る</a></p>
</body>
</html>
EOF
}


# Print error
sub print_message_error(){
(my $caller_str, my $message_str) = (@_);
# print "Content-type: text/html; charset=UTF-8\n\n";
print <<"EOF";
<!DOCTYPE html>
<html>
<head>
<title> SVNM: 仮想ネットワーク作成結果 </title>
</head>
<body>
<h1>仮想ネットワーク作成結果</h1>
<p style="color: red;"><b>[エラー]: 仮想ネットワークが作成できませんでした。</b></p>
<p><b>[エラーメッセージ]: $message_str</b></p>
<p><b>[エラー箇所]: $caller_str</b></p>
<ul>
<li>仮想ネットワーク名: $slice_name</li>
<li>ホスト数: $number_of_hosts</li>
</ul>
<p><a href="../html/index.html">メニューへ戻る</a></p>
</body>
</html>
EOF
exit;
}


# MAC Util
sub mac_string_to_int(){
    my ($string) = @_;

    $string =~ s/://g;

    return hex( "0x" . $string);
}


sub int_to_mac_string(){
    my ($mac) = @_;

    my $string = sprintf("%04x%08x", $mac >> 32, $mac & 0xffffffff);
    $string =~ s/(.{2})(.{2})(.{2})(.{2})(.{2})(.{2})/$1:$2:$3:$4:$5:$6/;

    return $string;
}
