$LOAD_PATH.unshift File.join(__dir__, '../vendor/topology/lib')
require 'fdb'
require 'topology_controller'


# An OpenFlow controller that emulates multiple switches.
# Convention: aggregate switches have datapath IDs > 16, TOR switches: < 16 
# All end networks are assumed to have a mask of 255.255.255.0
class MultiBalancedSwitch < Trema::Controller
  timer_event :age_fdbs, interval: 5.sec
  timer_event :lldp_discovery, interval: 1.sec
  attr_reader :topo, :tor_switches, :aggr_switches

  def start(_argv)
    @fdbs = {}
    @tor_switches = {}
    @aggr_switches = {}
    @topo = start_topology _argv
    logger.info "#{name} started."
  end

  def switch_ready(datapath_id)
    @topo.switch_ready(datapath_id)
    @fdbs[datapath_id] = FDB.new
    #distinguishing between top-of-rack and aggregate switches
    switch_obj = SWITCH.fetch datapath_id
    if datapath_id > 16
      aggr_switches[datapath_id] = switch_obj
    else
      tor_switches[datapath_id] = switch_obj
    end
  end

  def features_reply(datapath_id, features_reply)
    topo.features_reply(datapath_id, features_reply)
  end

  def packet_in(datapath_id, packet_in)
    logger.info("Packet arrived into #{datapath_id} in port #{packet_in.in_port} from #{packet_in.source_ip_address} to #{packet_in.destination_ip_address}") unless packet_in.lldp?  
    topo.packet_in(datapath_id, packet_in)
    return if packet_in.destination_mac.reserved?
    @fdbs.fetch(datapath_id).learn(packet_in.source_mac, packet_in.in_port)
    flow_mod_and_packet_out packet_in
  end

  def age_fdbs
    @fdbs.each_value(&:age)
  end

  private

  def flow_mod_and_packet_out(packet_in)
    dpid = packet_in.dpid
    port_no = @fdbs.fetch(packet_in.dpid).lookup(packet_in.destination_mac) ||
      host_port_for(dpid, packet_in.destination_mac)
    # if the target machine is connected to the same switch, simply forward the packet
    # otherwise send it up/down the topology tree
    unless port_no
      if tor_switch?(dpid)
        logger.info("Received packet at the TOR switch #{dpid}")
        if same_subnet?(packet_in.source_ip_address, packet_in.destination_ip_address)
          logger.info("Dest and target are on the same subnet, flooding to hosts")
          return flood_to_hosts_only(dpid, packet_in)
        end

        #TODO balance the load! 
        uplink = uplinks_for(dpid).first
        logger.info("selected uplink: #{uplink.inspect}")
        port_no = uplink && link_port_for(uplink, dpid)
      else
        logger.info("Received packet at the aggregation switch #{dpid}")

      end
    end
    flow_mod(packet_in, port_no)
    packet_out(packet_in, port_no)
  end

  def same_subnet?(ip1, ip2)
    ip1.mask(24) == ip2.mask(24)
  end

  def tor_switch?(dpid)
    tor_switches.has_key?(dpid)
  end

  def aggr_switch?(dpid)
    aggr_switches.has_key?(dpid)
  end

  def host_port_for(dpid, mac)
    host = topo.topology.hosts.find do |host| 
      host.first == mac && host[2] == dpid
    end
    host && host[3]
  end

  def link_port_for(link, dpid)
    link.dpid_a == dpid ? link.port_a : link.port_b
  end

  def flood_to_hosts_only(dpid, packet)
    uplinks_ports = uplinks_for(dpid).map do |link|
      link_port_for(link, dpid)
    end
    # sending packet to all ports except origin and uplinks
    topo.topology.ports[dpid].each do |port| 
      unless uplinks_ports.include?(port.port_no) || port.port_no == packet.in_port
        packet_out packet, port.port_no
      end
    end
  end

  def uplinks_for(tor_dpid)
    topo.topology.links.select do |link| 
      link.dpid_a == tor_dpid && aggr_switch?(link.dpid_b) ||
      link.dpid_b == tor_dpid && aggr_switch?(link.dpid_a)
    end
  end

  def downlink_for(aggr_dpid, dest_mac)
    host = topo.topology.hosts.find {|host_record| host_record.first == dest_mac }
    return unless host
    tor_dpid = host[2]
    topo.topology.links.find do |link|
      link.dpid_a == aggr_dpid && link.dpid_b == tor_dpid
    end
  end

  def flow_mod(packet_in, port_no)
    send_flow_mod_add(
      packet_in.datapath_id,
      match: ExactMatch.new(packet_in),
      actions: SendOutPort.new(port_no)
    )
  end

  def packet_out(packet_in, port_no)
    send_packet_out(
      packet_in.datapath_id,
      packet_in: packet_in,
      actions: SendOutPort.new(port_no)
    )
  end

  def start_topology(_argv)
    observer = self
    topo_controller = TopologyController.new do |topo|
      topo.add_observer observer
    end
    topo_controller.start _argv
    topo_controller
  end

  def lldp_discovery
    topo.flood_lldp_frames
  end
end

#monkey-patch for topology - they seem to have forgotten to add the hosts accessor
class Topology
  attr_reader :hosts
end
