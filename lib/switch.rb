class Switch
  MAX_TOR_SWITCH_DPID = 16

  def self.create(dpid, topology, fdb)
    #distinguishing between top-of-rack and aggregate switches
    if dpid < MAX_TOR_SWITCH_DPID
      TorSwitch.new(dpid, topology, fdb)
    else
      AggregateSwitch.new(dpid, topology, fdb)
    end
  end

  attr_reader :dpid, :topology, :fdb

  def initialize(dpid, topology, fdb)
    @dpid = dpid
    @topology = topology
    @fdb = fdb
  end

  def forward_ports_for(packet)
    host_port = fdb.lookup(packet.destination_mac) ||
      host_port_for(packet.destination_mac)
    if host_port
      [host_port]
    else
      port_missing(packet).reject { |port_no| port_no == packet.in_port }
    end
  end

  def port_missing(packet)
    raise NotImplementedError
  end

  def flood_ports
    raise NotImplementedError
  end

  def age_fdb
    fdb.age
  end

  protected

  def host_port_for(mac)
    host = topology.hosts.find do |host| 
      host.first == mac && host[2] == dpid
    end
    return unless host 
    port_no = host[3]
    fdb.learn(mac, port_no)
    port_no
  end

  def link_port_for(link)
    link.dpid_a == dpid ? link.port_a : link.port_b
  end
end
