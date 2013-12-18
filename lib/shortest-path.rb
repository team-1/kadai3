# -*- coding: utf-8 -*-
require 'rubygems'

require 'dijkstraruby'

#
# Shortest Path information containing path information
# between all switches.
#
class ShortestPath
  attr_accessor :graph

  def initialize
    @graph = nil
    @link_switches = []
  end

  def calc_shortest_path(topology)
    @link_switches = []
    topology.links.each do |each|
      temp_link = [[each.dpid_a, each.dpid_b, each.weight]]
      @link_switches += temp_link unless each.is_connected_host
    end
    @graph = Dijkstraruby::Graph.new(@link_switches)
  end

  def get_shortest_path(topology, src, dest)
    calc_shortest_path topology
    result = @graph.shortest_path src, dest
    links_on_path = separate_each_link_on_path result
    combine_switch_and_port topology, links_on_path
  end

  private

  def separate_each_link_on_path(result)
    links_on_path = []
    i = 0
    while i < result[0].size - 1
      links_on_path += [[result[0][i], result[0][i + 1]]]
      i += 1
    end
    links_on_path
  end

  def combine_switch_and_port(topology, links_on_path)
    links_result = []
    links_on_path.each do |each|
      topology.links.each do |each2|
        if (each2.dpid_a == each[0]) && (each2.dpid_b == each[1])
          links_result += [[each2.dpid_a, each2.port_a]]
          break
        end
      end
    end
    links_result
  end
end

### Local variables:
### mode: Ruby
### coding: utf-8-unix
### indent-tabs-mode: nil
### End:
