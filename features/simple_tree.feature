Feature: "Simple Tree Controller" example
  Background:
    Given I set the environment variables to:
      | variable         | value |
      | TREMA_LOG_DIR    | .     |
      | TREMA_PID_DIR    | .     |
      | TREMA_SOCKET_DIR | .     |
    And a file named "trema.conf" with:
      """ruby
      vswitch("tor1") {
        datapath_id "0x1"
      }

      vswitch("tor2") {
        datapath_id "0x2"
      }

      vswitch("aggr1") {
        datapath_id "0x11"
      }

      vswitch("aggr2") {
        datapath_id "0x12"
      }

      vhost("host1-1") {
        ip "192.168.3.1"
        mac "00:00:00:00:00:01"
      }

      vhost("host1-2") {
        ip "192.168.3.2"
        mac "00:00:00:00:00:02"
      }

      vhost("host2-1") {
        ip "192.168.4.1" 
        mac "00:00:00:00:01:01"
      }

      vhost("host2-2") {
        ip "192.168.4.2"
        mac "00:00:00:00:01:02"
      }

      link "tor1", "host1-2"
      link "tor1", "host1-1"
      link "tor1", "aggr1"
      link "tor1", "aggr2"
      link "tor2", "host2-1"
      link "tor2", "host2-2"
      link "tor2", "aggr1"
      link "tor2", "aggr2"
      """ 

  @sudo
  Scenario: Hosts on the same TOR switch can communicate, as well as hosts on different TOR switches
    Given I trema run "lib/simple_tree.rb" with the configuration "trema.conf"
    When I successfully run `trema send_packets --source host1-1 --dest host1-2 --npackets 2`
    Then the total number of received packets should be:
      | host1-1 | host1-2 | host2-1 | host2-2 |
      |       0 |       2 |       0 |       0 |
    When I successfully run `trema send_packets --source host2-1 --dest host2-2 --npackets 3`
    Then the total number of received packets should be:
      | host1-1 | host1-2 | host2-1 | host2-2 |
      |       0 |       2 |       0 |       3 |
    When I successfully run `trema send_packets --source host2-2 --dest host1-1 --npackets 2`
    Then the total number of received packets should be:
      | host1-1 | host1-2 | host2-1 | host2-2 |
      |       2 |       2 |       0 |       3 |
    When I successfully run `trema send_packets --source host1-2 --dest host2-1 --npackets 4`
    Then the total number of received packets should be:
      | host1-1 | host1-2 | host2-1 | host2-2 |
      |       2 |       2 |       4 |       3 |
    When I successfully run `trema send_packets --source host1-1 --dest host2-2 --npackets 1`
    Then the total number of received packets should be:
      | host1-1 | host1-2 | host2-1 | host2-2 |
      |       2 |       2 |       4 |       4 |

  @sudo
  Scenario: One of the aggregate switches dies, the other is picked up in 5s
    Given I trema run "lib/simple_tree.rb" with the configuration "trema.conf"
    And I successfully run `trema send_packets --source host1-1 --dest host2-2 --npackets 1`
    When I successfully run `trema stop aggr1`
    And sleep 5
    And I successfully run `trema send_packets --source host1-1 --dest host2-2 --npackets 1`
    Then the total number of received packets should be:
        | host1-1 | host1-2 | host2-1 | host2-2 |
        |       0 |       0 |       0 |       2 |

  @sudo
  Scenario: One of the TOR-to-aggregate links dies, the other switch is picked up in 5s, the other still works
    Given I trema run "lib/simple_tree.rb" with the configuration "trema.conf"
    And I successfully run `trema send_packets --source host1-1 --dest host2-2 --npackets 1`

    When I delete the link between "aggr1" and "tor1"
    And sleep 5
    And I successfully run `trema send_packets --source host1-1 --dest host2-2 --npackets 2`
    Then the total number of received packets should be:
        | host1-1 | host1-2 | host2-1 | host2-2 |
        |       0 |       0 |       0 |       3 |

    When I successfully run `trema send_packets --source host2-1 --dest host1-2 --npackets 2`
    Then the total number of received packets should be:
        | host1-1 | host1-2 | host2-1 | host2-2 |
        |       0 |       2 |       0 |       3 |