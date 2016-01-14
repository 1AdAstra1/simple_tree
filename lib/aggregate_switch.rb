class AggregateSwitch < Switch

  def port_missing(packet)
    if downlink = downlink_for(packet.destination_mac)
      # we don't know the particular port in _this_ switch, but we see the host with such 
      # MAC address has already already appeared in the global topology's host registry
      # (perhaps sent a packet via another switch)
      port_no = link_port_for(downlink)
      fdb.learn(packet.destination_mac, port_no)
      return [port_no]
    end

    # otherwise just send the packet to all TOR switches except for the source
    flood_ports
  end

  def flood_ports
    downlink_ports = downlinks.map { |link| link_port_for(link) }
  end

  private

  def downlinks
    topology.links.select do |link| 
      (link.dpid_a == dpid && link.dpid_b < MAX_TOR_SWITCH_DPID) ||
      (link.dpid_b == dpid && link.dpid_a < MAX_TOR_SWITCH_DPID)
    end
  end

  def downlink_for(dest_mac)
    host = topology.hosts.find {|host_record| host_record.first == dest_mac }
    return unless host
    tor_dpid = host[2]
    topology.links.find do |link|
      link.dpid_a == dpid && link.dpid_b == tor_dpid ||
      link.dpid_b == dpid && link_dpid_a == tor_dpid
    end
  end
end
