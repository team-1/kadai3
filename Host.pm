#
# Host configuration module for sliceable switch application.
#
# Author: Yasunobu Chiba,
#         Masanori Ishino
#
# Copyright (C) 2011-2012 NEC Corporation
#           (C) 2013-2014 Masanori Ishino
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License, version 2, as
# published by the Free Software Foundation.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License along
# with this program; if not, write to the Free Software Foundation, Inc.,
# 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.
#

package Host;

use strict;
use bignum;
use DBI;
use Carp qw(croak);

use constant{
    SUCCEEDED => 0,
    FAILED => -1,
    NO_HOST_FOUND => -2
};

# For ``is_occupied"
use constant{
    FREE => 0,
    OCCUPIED => 1
};

my $Debug = 0;

sub new(){
    my ($class, $db_file) = @_;
    my $hash = {
	dbh => undef
    };

    $hash->{'dbh'} = DBI->connect("dbi:SQLite:dbname=$db_file", "", "");

    if(!defined($hash->{'dbh'})){
	return undef;
    }
    $hash->{'dbh'}->sqlite_busy_timeout(100);
    $hash->{'dbh'}->do("PRAGMA synchronous=OFF");

    bless($hash, $class);
}


sub close(){
    my $self = shift;

    if(defined($self->{'dbh'})){
	$self->{'dbh'}->disconnect();
    }
}


sub get_hosts(){
    my $self = shift;

    my $sth = $self->{'dbh'}->prepare("SELECT * FROM hosts");
    my $ret = $sth->execute();

    my @hosts = ();
    while(my @row = $sth->fetchrow_array){
	my %host = ();
	$host{'mac'} = int_to_mac_string($row[0]);
	$host{'datapath_id'} = $row[1];
	$host{'port'} = $row[2];
	$host{'is_occupied'} = $row[3];
	push(@hosts, \%host);
    }

    return @hosts;
}


sub list_hosts(){
    my $self = shift;

    my @hosts = $self->get_hosts();

    if(@hosts == 0){
	info("No Hosts found.");
	return 0;
    }

    my $out = sprintf("%20s\t%8s\t%8s\t%8s\n", "MAC", "Datapath ID", "Port", "is_occpuied");
    foreach my $host (@hosts){
	$out .= sprintf("%20s\t%8s\t%8d\t%8d\n", 
			${$host}{'mac'}, 
			${$host}{'datapath_id'}, 
			${$host}{'port'}, 
			${$host}{'is_occupied'});
    }

    info($out);

    return 0;
}



sub add_host(){
    my($self, $mac, $datapath_id, $port, $is_occupied) = @_;

    if(!defined($is_occupied)){
	$is_occupied = FREE;
    }

    my $ret = $self->{'dbh'}->do("INSERT INTO hosts (mac,datapath_id,port,is_occupied) values ($mac,$datapath_id,$port,$is_occupied)");
    if($ret <= 0){
	return FAILED;
    }

    my $macstr = int_to_mac_string($mac);
    debug("New Host (MAC address: $macstr) is added successfully.");

    return SUCCEEDED;
}


sub delete_host(){
    my($self, $mac) = @_;

    my $ret = $self->{'dbh'}->do("DELETE FROM hosts WHERE mac = $mac");
    if($ret <=0){
	return FAILED;
    }

    my $macstr = int_to_mac_string($mac);
    debug("Host (MAC address: $macstr) is deleted successfully.");

    return SUCCEEDED;
}

# 指定した MAC を持つホストの仕様状況 ($is_occupied <= FREE or OCCUPIED) を変更する
sub update_host_state(){
    my($self, $mac, $is_occupied) = @_;

    if(!($is_occupied == FREE || $is_occupied == OCCUPIED)){
	debug("Wrong state value for a host.");
	return FAILED;
    }

    my $sth_confirm = $self->{'dbh'}->prepare("SELECT mac FROM hosts WHERE mac = $mac");
    my $ret_confirm = $sth_confirm->execute();
    my $row_confirm = $sth_confirm->fetch();
    if(!defined($row_confirm)){
	return NO_HOST_FOUND;
    }

    my $statement = "UPDATE hosts SET is_occupied = $is_occupied WHERE mac = $mac";
    my $ret = $self->{'dbh'}->do($statement);
    if($ret <=0){
	return FAILED;
    }

    my $macstr = int_to_mac_string($mac);
    debug("State of Host (MAC address: $macstr) is updated successfully.");
    debug("Set to $is_occupied.");

    return SUCCEEDED;
}


# 未使用状態のホスト数を得る
sub get_number_of_available_hosts(){
    my($self) = @_;
    my $number_of_available_hosts = 0;

    my $statement = "SELECT COUNT(*) FROM hosts WHERE is_occupied = 0";
    my $array_ref = $self->{'dbh'}->selectrow_arrayref($statement);
    $number_of_available_hosts = $array_ref->[0];

    return $number_of_available_hosts;
}

# 指定した個数の未使用状態のホストの MAC アドレスを得る
sub get_mac_of_some_available_hosts(){
    my($self, $number_of_ordered_hosts) = @_;
    my @macs_available = ();

    if($number_of_ordered_hosts < 1){
	debug("Number of ordered hosts should be >= 1.");
	return ();
    }
    
    # 未使用ノードが指定個数取得可能かどうか確認
    my $current_number = $self->get_number_of_available_hosts();
    if($current_number < $number_of_ordered_hosts){
	debug("Could not get $number_of_ordered_hosts available hosts.");
	return ();
    }
    
    # 確保した未使用ノードの MAC アドレスを配列に得る
    my $statement_body = "SELECT mac FROM hosts WHERE is_occupied = 0";
    my $statement_options = "LIMIT $number_of_ordered_hosts";	
    my $statement = $statement_body." ".$statement_options;
    my $sth = $self->{'dbh'}->prepare($statement);
    my $ret = $sth->execute();

    while (my $arr_ref = $sth->fetchrow_arrayref){
	my ($mac) = @$arr_ref;
	push(@macs_available, $mac);
    }

    return @macs_available;
}

# 指定した個数の未使用状態のホストの MAC アドレス (文字列) を得る
sub get_mac_str_of_some_available_hosts(){
    my($self, $number_of_ordered_hosts) = @_;
    my @macs_available = ();
    my @macs_str_available = ();

    # 未使用ホストの MAC アドレスを文字列の形で得る
    @macs_available = $self->get_mac_of_some_available_hosts($number_of_ordered_hosts);
    if(@macs_available){
    	for my $temp_mac (@macs_available){
    	    my $temp_mac_str = int_to_mac_string($temp_mac);
    	    push(@macs_str_available, $temp_mac_str);
    	}
    }

    return @macs_str_available;
}

# sub create_slice(){
#     my ($self, $slice_id, $description) = @_;

#     my $slice_number = 1;
#     my $sth = $self->{'dbh'}->prepare("SELECT MAX(number) FROM slices");
#     my $ret = $sth->execute();
#     my $row = $sth->fetch();
#     $slice_number = $row->[0] + 1 if defined($row->[0]);

#     if(!defined($description)){
# 	$description = "";
#     }
#     $description =~ s/'/''/;

#     debug("creating a slice (number = %u, id = %s, description = %s).",
# 	  $slice_number, $slice_id, $description);

#     $ret = $self->{'dbh'}->do("INSERT INTO slices VALUES ($slice_number,'$slice_id','$description')");
#     if($ret <= 0){
# 	return FAILED;
#     }
#     debug("Slice created successfully.");

#     return SUCCEEDED;
# }


# sub update_slice(){
#     my ($self, $slice_id, $description) = @_;

#     if(!defined($description)){
# 	$description = "";
#     }
#     $description =~ s/'/''/;

#     my $slice_number;
#     if($self->get_slice_number_by_id($slice_id, \$slice_number) < 0){
# 	return NO_SLICE_FOUND;
#     }

#     debug("updating a slice (number = %u, id = %s, description = %s).",
# 	  $slice_number, $slice_id, $description);

#     my $ret = $self->{'dbh'}->do("UPDATE slices SET description = '$description' WHERE number = $slice_number");
#     if($ret <= 0){
# 	return FAILED;
#     }
#     debug("Slice updated successfully.");

#     return SUCCEEDED;
# }


# sub destroy_slice(){
#     my ($self, $slice_id) = @_;

#     debug("destroying a slice (id = %s).", $slice_id);

#     my $slice_number;
#     if($self->get_slice_number_by_id($slice_id, \$slice_number) < 0){
# 	return NO_SLICE_FOUND;
#     }

#     my $errors = 0;

#     my $ret = $self->{'dbh'}->do("DELETE FROM slices WHERE number = $slice_number");
#     if($ret <= 0){
# 	$errors++;
#     }

#     $ret = $self->{'dbh'}->do("DELETE FROM bindings WHERE slice_number = $slice_number");
#     if($ret < 0){
# 	$errors++;
#     }

#     if($errors){
# 	return FAILED;
#     }
#     debug("Slice destroyed successfully.");

#     return SUCCEEDED;
# }


# sub get_slices(){
#     my $self = shift;

#     my $sth = $self->{'dbh'}->prepare("SELECT * FROM slices");
#     my $ret = $sth->execute();

#     my @slices = ();
#     while(my @row = $sth->fetchrow_array){
# 	my %slice = ();
# 	$slice{'id'} = $row[1];
# 	$slice{'description'} = $row[2];
# 	push(@slices, \%slice);
#     }

#     return @slices;
# }

# sub list_slices(){
#     my $self = shift;

#     my @slices = $self->get_slices();

#     if(@slices == 0){
# 	info("No slice found.");
# 	return 0;
#     }

#     my $out = sprintf("%32s\t%32s\n", "ID", "Description");
#     foreach my $slice (@slices){
# 	$out .= sprintf("%32s\t%32s\n", ${$slice}{'id'}, ${$slice}{'description'});
#     }

#     info($out);

#     return 0;
# }


# sub add_port(){
#     my($self, $id, $slice_id, $dpid, $port, $vid) = @_;

#     my $slice_number;
#     if($self->get_slice_number_by_id($slice_id, \$slice_number) < 0){
# 	return NO_SLICE_FOUND;
#     }

#     my $ret = $self->{'dbh'}->do("INSERT INTO bindings (type,datapath_id,port,vid,slice_number,id) values (" . BINDING_TYPE_PORT . ",$dpid,$port,$vid,$slice_number,'$id')");
#     if($ret <= 0){
# 	return FAILED;
#     }
#     debug("Port is added successfully.");

#     return SUCCEEDED;
# }


# sub delete_port(){
#     my($self, $slice_id, $dpid, $port, $vid) = @_;

#     my $slice_number;
#     if($self->get_slice_number_by_id($slice_id, \$slice_number) < 0){
# 	return NO_SLICE_FOUND;
#     }

#     my $ret = $self->{'dbh'}->do("DELETE FROM bindings WHERE type = " . BINDING_TYPE_PORT . " AND datapath_id = $dpid AND port = $port AND vid = $vid AND slice_number = $slice_number");
#     if($ret <= 0){
# 	return FAILED;
#     }
#     debug("Port is deleted successfully.");

#     return SUCCEEDED;
# }




# sub add_mac_on_port(){
#     my($self, $id, $slice_id, $port_id, $mac) = @_;

#     my $slice_number;
#     if($self->get_slice_number_by_id($slice_id, \$slice_number) < 0){
# 	return NO_SLICE_FOUND;
#     }

#     my $statement = "SELECT * FROM bindings WHERE slice_number = $slice_number AND id = '$port_id'";
#     my $sth = $self->{'dbh'}->prepare($statement);
#     my $ret = $sth->execute();

#     my ($dpid, $port, $vid) = ();
#     my $found = 0;
#     while(my @row = $sth->fetchrow_array){
# 	$dpid = $row[1];
# 	$port = $row[2];
# 	$vid = $row[3];
# 	$found++;
#     }

#     if($found == 0){
# 	return NO_BINDING_FOUND;
#     }

#     $ret = $self->{'dbh'}->do("INSERT INTO bindings (type,datapath_id,port,vid,mac,slice_number,id) values (" . BINDING_TYPE_PORT_MAC . ",$dpid,$port,$vid,$mac,$slice_number,'$id')");
#     if($ret <= 0){
# 	return FAILED;
#     }
#     debug("Port-mac is added successfully.");

#     return SUCCEEDED;
# }


# sub delete_mac_on_port(){
#     my($self, $slice_id, $port_id, $mac) = @_;

#     my $slice_number;
#     if($self->get_slice_number_by_id($slice_id, \$slice_number) < 0){
# 	return NO_SLICE_FOUND;
#     }

#     my $statement = "SELECT * FROM bindings WHERE slice_number = $slice_number AND id = '$port_id'";
#     my $sth = $self->{'dbh'}->prepare($statement);
#     my $ret = $sth->execute();

#     my ($dpid, $port, $vid) = ();
#     my $found = 0;
#     while(my @row = $sth->fetchrow_array){
# 	$dpid = $row[1];
# 	$port = $row[2];
# 	$vid = $row[3];
# 	$found++;
#     }

#     if($found == 0){
# 	return NO_BINDING_FOUND;
#     }

#     $ret = $self->{'dbh'}->do("DELETE FROM bindings WHERE type = " . BINDING_TYPE_PORT_MAC . " AND datapath_id = $dpid AND port = $port AND vid = $vid AND slice_number = $slice_number AND mac = $mac");
#     if($ret <= 0){
# 	return FAILED;
#     }
#     debug("Port-mac is deleted successfully.");

#     return SUCCEEDED;
# }


# sub delete_binding_by_id(){
#     my($self, $slice_id, $id) = @_;

#     my $slice_number;
#     if($self->get_slice_number_by_id($slice_id, \$slice_number) < 0){
# 	return NO_SLICE_FOUND;
#     }

#     my $err;
#     $self->get_bindings(undef, $slice_id, $id, \$err);
#     if($err == NO_SLICE_FOUND || $err == NO_BINDING_FOUND){
# 	return $err;
#     }

#     my $ret = $self->{'dbh'}->do("DELETE FROM bindings WHERE slice_number = $slice_number AND id = '$id'");
#     if($ret <= 0){
# 	return FAILED;
#     }
#     debug("Binding is deleted successfully.");

#     return SUCCEEDED;
# }


# sub get_bindings(){
#     my ($self, $type, $slice_id, $id, $err) = @_;

#     if(defined($err)){
# 	${$err} = SUCCEEDED;
#     }

#     my $slice_number;
#     if($self->get_slice_number_by_id($slice_id, \$slice_number) < 0){
# 	if(defined($err)){
# 	    ${$err} = NO_SLICE_FOUND;
# 	}
# 	return;
#     }

#     my $statement = "SELECT * FROM bindings WHERE slice_number = $slice_number";

#     if(defined($type) && $type == BINDING_TYPE_PORT){
# 	$statement .= " AND type = " . BINDING_TYPE_PORT;
#     }
#     elsif(defined($type) && $type == BINDING_TYPE_MAC){
# 	$statement .= " AND type = " . BINDING_TYPE_MAC;
#     }
#     elsif(defined($type) && $type == BINDING_TYPE_PORT_MAC){
# 	$statement .= " AND type = " . BINDING_TYPE_PORT_MAC;
#     }

#     if(defined($id)){
# 	$statement .= " AND id = '$id'";
#     }

#     my $sth = $self->{'dbh'}->prepare($statement);
#     my $ret = $sth->execute();

#     my %bindings = ();
#     while(my @row = $sth->fetchrow_array){
# 	$id = $row[5];
# 	$bindings{$id}{'type'} = $row[0];
# 	$bindings{$id}{'datapath_id'} = $row[1];
# 	$bindings{$id}{'port'} = $row[2];
# 	$bindings{$id}{'vid'} = $row[3];
# 	$bindings{$id}{'mac'} = int_to_mac_string($row[4]);
#     }

#     if(!%bindings){
# 	if(defined($err)){
# 	    ${$err} = NO_BINDING_FOUND;
# 	}
#     }

#     return %bindings;
# }


# sub show_description(){
#     my ($self, $slice_id) = @_;

#     my $description = "";
#     my $ret = $self->get_slice_description_by_id($slice_id, \$description);
#     if($ret == NO_SLICE_FOUND){
# 	error("No slice found");
# 	return FAILED;
#     }

#     info("[Description]\n%s\n", $description);

#     return SUCCEEDED;
# }


# sub show_bindings(){
#     my ($self, $type, $slice_id, $id) = @_;

#     my $err;
#     my %bindings = $self->get_bindings($type, $slice_id, $id, \$err);

#     if($err == NO_SLICE_FOUND){
# 	error("No slice found");
# 	return FAILED;
#     }
#     elsif($err == NO_BINDING_FOUND){
# 	info("No bindings found.");
# 	return SUCCEEDED;
#     }

#     my $port_count = 0;
#     my $mac_count = 0;
#     my $port_mac_count = 0;
#     my $port_out = sprintf("%24s\t%20s\t%8s\t%8s\n", "ID", "Datapath ID", "Port", "VID" );
#     my $mac_out = sprintf("%24s\t%20s\n", "ID", "MAC");
#     my $port_mac_out = sprintf("%24s\t%20s\t%8s\t%8s\t%20s\n", "ID", "Datapath ID", "Port", "VID", "MAC" );

#     foreach my $id (keys(%bindings)){
# 	if($bindings{$id}{'type'} == BINDING_TYPE_PORT){
# 	    $port_count++;
# 	    $port_out .= sprintf("%24s\t%#20x\t%8u\t%8u\n", $id,
# 				 $bindings{$id}{'datapath_id'},
# 				 $bindings{$id}{'port'},
# 				 $bindings{$id}{'vid'});
# 	}
# 	elsif($bindings{$id}{'type'} == BINDING_TYPE_MAC){
# 	    $mac_count++;
# 	    $mac_out .= sprintf("%24s\t%20s\n", $id, $bindings{$id}{'mac'});
# 	}
# 	elsif($bindings{$id}{'type'} == BINDING_TYPE_PORT_MAC){
# 	    $port_mac_count++;
# 	    $port_mac_out .= sprintf("%24s\t%#20x\t%8u\t%8u\t%20s\n", $id,
# 				     $bindings{$id}{'datapath_id'},
# 				     $bindings{$id}{'port'},
# 				     $bindings{$id}{'vid'},
# 				     $bindings{$id}{'mac'});
# 	}
#     }

#     if($port_count == 0){
# 	$port_out = "No bindings found.\n";
#     }
#     if($mac_count == 0){
# 	$mac_out = "No bindings found.\n";
#     }
#     if($port_mac_count == 0){
# 	$port_mac_out = "No bindings found.\n";
#     }

#     if($type & BINDING_TYPE_PORT){
# 	info("[Port-based bindings]");
# 	info($port_out);
#     }
#     if($type & BINDING_TYPE_MAC){
# 	info("[MAC-based bindings]");
# 	info($mac_out);
#     }
#     if($type & BINDING_TYPE_PORT_MAC){
# 	info("[MAC-based bindings on ports]");
# 	info($port_mac_out);
#     }

#     return SUCCEEDED;
# }


# sub get_slice_number_by_id(){
#     my $self = shift;
#     my $id = shift;
#     my $number = shift;

#     my $sth = $self->{'dbh'}->prepare("SELECT number FROM slices WHERE id = '$id'");
#     my $ret = $sth->execute();
#     my $row = $sth->fetch();
#     if(!defined($row)){
# 	return NO_SLICE_FOUND;
#     }
#     ${$number} = $row->[0];

#     return SUCCEEDED;
# }


# sub get_slice_id_by_number(){
#     my $self = shift;
#     my $number = shift;
#     my $id = shift;

#     my $sth = $self->{'dbh'}->prepare("SELECT id FROM slices WHERE number = $number");
#     my $ret = $sth->execute();
#     my $row = $sth->fetch();
#     if(!defined($row)){
# 	return NO_SLICE_FOUND;
#     }
#     ${$id} = $row->[0];

#     return SUCCEEDED;
# }


# sub get_slice_description_by_id(){
#     my $self = shift;
#     my $id = shift;
#     my $description = shift;

#     my $sth = $self->{'dbh'}->prepare("SELECT description FROM slices WHERE id = '$id'");
#     my $ret = $sth->execute();
#     my $row = $sth->fetch();
#     if(!defined($row)){
# 	return NO_SLICE_FOUND;
#     }
#     ${$description} = $row->[0];

#     return SUCCEEDED;
# }


sub int_to_mac_string(){
    my ($mac) = @_;

    my $string = sprintf("%04x%08x", $mac >> 32, $mac & 0xffffffff);
    $string =~ s/(.{2})(.{2})(.{2})(.{2})(.{2})(.{2})/$1:$2:$3:$4:$5:$6/;

    return $string;
}


sub debug(){
    if($Debug){
	printf(@_);
	printf("\n");
    }
}


sub info(){
    printf(@_);
    printf("\n");
}


sub error(){
    printf(STDERR @_);
    printf(STDERR "\n");
}


1;
