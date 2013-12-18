# -*- coding: utf-8 -*-
require 'rubygems'
require 'pio/lldp'

#
# Edges between two switches.
#
class Link
  attr_reader :dpid_a
  attr_reader :dpid_b
  attr_reader :port_a
  attr_reader :port_b
  attr_reader :is_connected_host
  attr_reader :weight

  def initialize(dpid, packet_in, is_connected_host = false)
    @dpid_a = 0
    @dpid_b = 0
    @port_a = 0
    @port_b = 0
    initialize_dpid_and_port(dpid, packet_in)
    @is_connected_host = is_connected_host
    @weight = 0
  end

  def ==(other)
    (@dpid_a == other.dpid_a) &&
      (@dpid_b == other.dpid_b) &&
      (@port_a == other.port_a) &&
      (@port_b == other.port_b)
  end

  def <=>(other)
    to_s <=> other.to_s
  end

  def to_s
    format_string_host = '%#s (port %d) <- weight: %d -> %#x (port %d)'
    format_string = '%#x (port %d) <- weight: %d -> %#x (port %d)'
    if dpid_a.class == String
      format format_string_host, dpid_a, port_a, weight, dpid_b, port_b
    else
      format format_string, dpid_a, port_a, weight, dpid_b, port_b
    end
  end

  def has?(dpid, port)
    ((@dpid_a == dpid) && (@port_a == port)) ||
      ((@dpid_b == dpid) && (@port_b == port))
  end

  def increment_weight
    @weight += 1
  end

  def decrement_weight
    @weight -= 1
    @weight = 0 if @weight < 0
  end

  def reset_weight
    @weight = 0
  end

  private

  def initialize_dpid_and_port(dpid, packet_in)
    if packet_in.ipv4?
      @dpid_a = packet_in.ipv4_saddr.to_s
      @port_a = 0
    elsif packet_in.lldp?
      lldp = Pio::Lldp.read(packet_in.data)
      @dpid_a = lldp.dpid
      @port_a = lldp.port_number
    end
    @dpid_b = dpid
    @port_b = packet_in.in_port
  end
end

### Local variables:
### mode: Ruby
### coding: utf-8-unix
### indent-tabs-mode: nil
### End:
