class TorSwitch < Switch

  #every end network is assumed to have up to 256 hosts
  DEFAULT_SUBNET_MASK_LENGTH = 24

  def port_missing(packet)
    if same_subnet?(packet.source_ip_address, packet.destination_ip_address) || 
        uplink_ports.include?(packet.in_port)
      # we don't know the particular port but we see it's on the same network,
      # or the packet came from an uplink (that doesn't know it either),
      # so we send it to all end hosts hoping that one of them replies to create a rule
      return flood_ports
    end

    # if we still don't know - let the first available uplink decide
    uplink = uplinks.first
    uplink && [link_port_for(uplink)]
  end

  def flood_ports
    topology.ports[dpid].reject { |port| uplink_ports.include?(port.port_no) }.map(&:port_no)
  end

  private

  def same_subnet?(ip1, ip2)
    ip1.mask(DEFAULT_SUBNET_MASK_LENGTH) == ip2.mask(DEFAULT_SUBNET_MASK_LENGTH)
  end

  def uplinks
    topology.links.select do |link| 
      (link.dpid_a == dpid && link.dpid_b > MAX_TOR_SWITCH_DPID) ||
      (link.dpid_b == dpid && link.dpid_a > MAX_TOR_SWITCH_DPID)
    end
  end

  def uplink_ports
    uplinks.map { |link| link_port_for(link) }
  end
end
