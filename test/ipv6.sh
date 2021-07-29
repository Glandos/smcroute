#!/bin/sh
# Verifies IPv6 (S,G) and (*,G) rules, both from .conf file and IPC, by
# injecting frames on one interface and verify reception on another.
#set -x

# shellcheck source=/dev/null
. "$(dirname "$0")/lib.sh"

print "Creating world ..."
topo basic

# IP world ...
ip addr add 2001:1::1/64 dev a1
ip addr add   fc00::1/64 dev a1
ip addr add 2001:2::1/64 dev a2
ip -br a

print "Creating config ..."
cat <<EOF > "/tmp/$NM/conf"
# ipv6 (*,G) multicast routing
phyint a1 enable
phyint a2 enable
mroute from a1 source fc00::1 group ff04:0:0:0:0:0:0:114 to a2
mroute from a1                group ff2e::42             to a2
EOF
cat "/tmp/$NM/conf"

print "Starting smcrouted ..."
../src/smcrouted -f "/tmp/$NM/conf" -n -N -P "/tmp/$NM/pid" -l debug -S "/tmp/$NM/sock" &
sleep 1

print "Starting collector ..."
tshark -c 12 -lni a2 -w "/tmp/$NM/pcap" 'dst ff04::114 or dst ff2e::42 or dst ff2e::43 or dst ff2e::44' 2>/dev/null &
sleep 1

../src/smcroutectl -S "/tmp/$NM/sock" add a1         ff2e::43 a2
../src/smcroutectl -S "/tmp/$NM/sock" add a1 fc00::1 ff2e::44 a2
show_mroute

print "Starting emitter ..."
ping -6 -c 3 -W 1 -I fc00::1   -t 3 ff04::114 >/dev/null
ping -6 -c 3 -W 1 -I 2001:1::1 -t 3 ff2e::42  >/dev/null
ping -6 -c 3 -W 1 -I 2001:1::1 -t 3 ff2e::43  >/dev/null
ping -6 -c 3 -W 1 -I fc00::1   -t 3 ff2e::44  >/dev/null
show_mroute

print "Analyzing ..."
lines1=$(tshark -r "/tmp/$NM/pcap" 2>/dev/null | grep ff04::114 | tee    "/tmp/$NM/result" | wc -l)
lines2=$(tshark -r "/tmp/$NM/pcap" 2>/dev/null | grep ff2e::42  | tee -a "/tmp/$NM/result" | wc -l)
lines3=$(tshark -r "/tmp/$NM/pcap" 2>/dev/null | grep ff2e::43  | tee -a "/tmp/$NM/result" | wc -l)
lines4=$(tshark -r "/tmp/$NM/pcap" 2>/dev/null | grep ff2e::44  | tee -a "/tmp/$NM/result" | wc -l)
cat "/tmp/$NM/result"
echo " => $lines1 for group ff04::114, expected => 3"
echo " => $lines2 for group ff2e::42,  expected => 2"
echo " => $lines3 for group ff2e::43,  expected => 2"
echo " => $lines4 for group ff2e::44,  expected => 3"

print "Cleaning up ..."
topo teardown

# one frame lost due to initial (*,G) -> (S,G) route setup
# no frames lost in pure (S,G) route
# shellcheck disable=SC2166 disable=SC2086
[ $lines1 -eq 3 -a $lines2 -ge 2 -a $lines3 -ge 2 -a $lines4 -eq 3 ] && exit 0
exit 1
