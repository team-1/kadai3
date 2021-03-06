# -*- coding: utf-8 -*-
$LOAD_PATH.unshift File.expand_path(File.join File.dirname(__FILE__), 'lib')

require 'rubygems'
require 'bundler/setup'

require 'command-line'
require 'topology'
require 'trema'
require 'trema-extensions/port'
require 'sqlite3'

#
# Sliceable Switch using LLDP to collect network topology information.
#
class SliceableSwitch < Controller
  periodic_timer_event :flood_lldp_frames, 1

  COOKIEVALUEFORFLOWTOHOST = 0
  FLOWHARDTIMEOUTTOHOST = 10
  INITIALFLOWHARDTIMEOUT = 10
  DIFFFLOWHARDTIMEOUT = 1

  SLICEDBFILENAME = 'slice.db'
  HOSTDBFILENAME  = 'host.db'

  def start
    @fdb = {}
    @command_line = CommandLine.new
    @command_line.parse(ARGV.dup)
    @topology = Topology.new(@command_line)
    begin
      @slice_db = SQLite3::Database.new SLICEDBFILENAME
    rescue SQLite3::SQLException => e
      puts e
    end
    begin
      @host_db = SQLite3::Database.new HOSTDBFILENAME
    rescue SQLite3::SQLException => e
      puts e
    end
  end

  def switch_ready(dpid)
    send_message dpid, FeaturesRequest.new
  end

  def features_reply(dpid, features_reply)
    features_reply.physical_ports.select(&:up?).each do |each|
      @topology.add_port each
    end
  end

  def switch_disconnected(dpid)
    @fdb.each_pair do |key, value|
      @fdb.delete(key) if value['dpid'] == dpid
    end
    @topology.delete_switch dpid
  end

  def port_status(dpid, port_status)
    updated_port = port_status.port
    return if updated_port.local?
    @topology.update_port updated_port
  end

  def packet_in(dpid, packet_in)
    if packet_in.ipv4?
      add_host_by_packet_in dpid, packet_in
      add_host_to_host_db packet_in.macsa, dpid, packet_in.in_port unless @fdb[packet_in.macsa]
      learn_new_host_fdb dpid, packet_in
      dest_host = @fdb[packet_in.macda]
      if dest_host
        is_same = is_belong_to_same_slice(packet_in.macsa, packet_in.macda)
        set_flow_for_routing dpid, packet_in, dest_host if is_same
      end
    elsif packet_in.lldp?
      @topology.add_link_by dpid, packet_in
    end
  end

  def flow_removed(dpid, flow_removed)
    if flow_removed.cookie.to_i > COOKIEVALUEFORFLOWTOHOST
      puts ">> cookie value of removed flow in dpid #{dpid.to_s} : " + flow_removed.cookie.to_s
      @topology.decrement_link_weight_on_flow dpid, flow_removed.cookie.to_i
    end
  end

  private

  def learn_new_host_fdb(dpid, packet_in)
    unless @fdb.key?(packet_in.macsa)
      new_host = { 'dpid' => dpid, 'in_port' => packet_in.in_port }
      @fdb[packet_in.macsa] = new_host
    end
  end

  def add_host_by_packet_in(dpid, packet_in)
    unless @topology.hosts.include?(packet_in.ipv4_saddr.to_s)
      @topology.add_host packet_in.ipv4_saddr.to_s
      @topology.add_host_to_link dpid, packet_in
    end
  end

  def set_flow_for_routing(dpid, packet_in, dest_host)
    if dest_host['dpid'] == dpid
      flow_mod_to_host(dpid, packet_in, dest_host['in_port'], FLOWHARDTIMEOUTTOHOST)
      packet_out(dpid, packet_in, dest_host['in_port'])
    else
      sp = @command_line.shortest_path
      links_result = sp.get_shortest_path(@topology, dpid, dest_host['dpid'])
      if links_result.length > 0
        temp_timeout = INITIALFLOWHARDTIMEOUT
        links_result.each do |each|
          flow_mod(each[0], packet_in, each[1].to_i, temp_timeout)
          @topology.increment_link_weight_on_flow each[0], each[1]
          temp_timeout = temp_timeout + DIFFFLOWHARDTIMEOUT
        end
      end
    end
  end

  def flood_lldp_frames
    @topology.each_switch do |dpid, ports|
      send_lldp dpid, ports
    end
  end

  def send_lldp(dpid, ports)
    ports.each do |each|
      port_number = each.number
      send_packet_out(
        dpid,
        actions: SendOutPort.new(port_number),
        data: lldp_binary_string(dpid, port_number)
      )
    end
  end

  def lldp_binary_string(dpid, port_number)
    destination_mac = @command_line.destination_mac
    if destination_mac
      Pio::Lldp.new(dpid: dpid,
                    port_number: port_number,
                    destination_mac: destination_mac.value).to_binary
    else
      Pio::Lldp.new(dpid: dpid, port_number: port_number).to_binary
    end
  end

  def flow_mod(dpid, message, port, timeout)
    send_flow_mod_add(
      dpid,
      hard_timeout: timeout,
      match: Match.new(dl_src: message.macsa.to_s, dl_dst: message.macda.to_s),
      actions: SendOutPort.new(port),
      cookie: port.to_i
    )
  end

  def flow_mod_to_host(dpid, message, port, timeout)
    send_flow_mod_add(
      dpid,
      hard_timeout: timeout,
      match: Match.new(dl_dst: message.macda.to_s),
      actions: SendOutPort.new(port),
      cookie: COOKIEVALUEFORFLOWTOHOST
    )
  end

  def packet_out(dpid, message, port)
    send_packet_out(
      dpid,
      packet_in: message,
      actions: SendOutPort.new(port)
    )
  end

  def is_belong_to_same_slice(macsa, macda)
    slice_number_src = get_slice_number_from_host_db(macsa)
    return false if slice_number_src < 0
    slice_number_dst = get_slice_number_from_host_db(macda)
    return false if slice_number_dst < 0
    puts "There are not src host (MAC: #{macsa.to_s}) and dst host (MAC: #{macda.to_s}) in same slice." unless slice_number_src == slice_number_dst
    result = (slice_number_src == slice_number_dst)? true : false
  end
  
  def get_slice_number_from_host_db(mac)
    s_num = -1
    # @slice_db.results_as_hash = true
    sql_result = @slice_db.get_first_value("SELECT B.slice_number FROM bindings B WHERE type = 2 AND mac = #{mac.to_i} LIMIT 1;")
    if sql_result
      puts sql_result
      s_num = sql_result.to_i
    else
      puts "There is not host (MAC: #{mac.to_s}) in binding DB."
    end
    s_num
  end

  def add_host_to_host_db(mac_str, dpid, port)
    mac = mac_string_to_int mac_str
    sql_statement_body = "INSERT INTO hosts (mac,datapath_id,port,is_occupied) "
    sql_statement_values = "values (#{mac},#{dpid},#{port},0)"
    sql_statement = sql_statement_body + sql_statement_values
    puts sql_statement
    begin
      @host_db.execute(sql_statement)
    rescue
      puts "Can not insert record of new host (MAC: #{mac_str}) into host DB."
    end
  end

  def mac_string_to_int(mac_str)
    temp_str = '0x' + (mac_str.to_s.split(':')).join
    return temp_str.hex
  end
end

### Local variables:
### mode: Ruby
### coding: utf-8-unix
### indent-tabs-mode: nil
### End:
