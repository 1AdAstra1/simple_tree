Simple Tree
===============

An OpenFlow controller that emulates multiple layer 2 learning switches connected as a simple 2-level tree topology, based on simple naming and numbering conventions. Multiple top-level switches are supported in order to provide fault-tolerance in case the current active switch is disabled for some reason.

The only layer 3 feature used is determining whether two IP addresses are on the same IP subnet.

Based on official Trema examples:

*[learning_switch](https://github.com/trema/learning_switch)
*[routing_switch](https://github.com/trema/routing_switch)
*[topology](https://github.com/trema/topology)

Prerequisites
-------------

* Ruby 2.0.0 or higher.
* [Open vSwitch][openvswitch] (`apt-get install openvswitch-switch`).

[openvswitch]: https://openvswitch.org/


Install
-------

```
$ git clone https://github.com/1AdAstra1/simple_tree.git
$ cd simple tree
$ bundle install
```


Play
----

The `lib/simple_tree.rb` is an OpenFlow controller implementation
that emulates a layer 2 switch. Run this like so:

```
$ ./bin/trema run ./lib/simple_tree.rb -c trema.multi.conf
```

Then send some packets from client1 to client2 (hosts on the same subnet), and show received packet
stats of client:

```
$ ./bin/trema send_packets --source client1 --dest client2 --npackets 10
$ ./bin/trema show_stats host2
Packets received:
 192.168.4.1 -> 192.168.4.2 = 10 packets
```

You can also send some packets from client1 to monitoring (a 'server' on a different subnet), and show received packet
stats of monitoring:

```
$ ./bin/trema send_packets --source client1 --dest monitoring --npackets 10
$ ./bin/trema show_stats monitoring
Packets received:
 192.168.4.1 -> 192.168.3.2 = 10 packets
```

Other usage cases can be seen in `features/simple_tree.feature` test file.

Enjoy!
