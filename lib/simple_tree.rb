$LOAD_PATH.unshift File.join(__dir__, '../vendor/topology/lib')
require 'fdb'
require 'topology_controller'
require 'switch'
require 'aggregate_switch'
require 'tor_switch'


# An OpenFlow controller that emulates a small 2-level tree topology.
# Convention: aggregate switches have datapath IDs > 16, TOR switches: < 16 
# All end networks are assumed to have a mask of 255.255.255.0
class SimpleTree < Trema::Controller
  timer_event :age_fdbs, interval: 5.sec
  timer_event :lldp_discovery, interval: 1.sec
  attr_reader :topo, :tor_switches, :aggr_switches, :all_switches

  def start(_argv)
    @all_switches = {}
    @topo = start_topology _argv
    logger.info "#{name} started."
  end

  def switch_ready(datapath_id)
    @topo.switch_ready(datapath_id)
    @all_switches[datapath_id] = Switch.create(datapath_id, @topo.topology, FDB.new)
  end

  def features_reply(datapath_id, features_reply)
    topo.features_reply(datapath_id, features_reply)
  end

  def packet_in(datapath_id, packet_in)
    logger.info("Packet arrived into switch #{datapath_id} in port #{packet_in.in_port} from #{packet_in.source_ip_address} to #{packet_in.destination_ip_address}") unless packet_in.lldp?  
    topo.packet_in(datapath_id, packet_in)
    return if packet_in.destination_mac.reserved?

    flow_mod_and_packet_out packet_in
  end

  def age_fdbs
    all_switches.each_value(&:age_fdb)
  end

  private

  def flow_mod_and_packet_out(packet_in)
    dpid = packet_in.dpid
    current_switch = all_switches[dpid]

    forward_ports = current_switch.forward_ports_for(packet_in)
    if(forward_ports.length == 1)
      #we know the only needed port and can set a kernel-space rule for it
      flow_mod(packet_in, forward_ports.first)
    end
    
    forward_ports.each do |port_no|
      packet_out(packet_in, port_no)
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
