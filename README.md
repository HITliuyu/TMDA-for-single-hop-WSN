# WSN_course_project
Time Division  Multiple Access Layer

In this project, I realized a simple power-saving time division mul-
tiple access (TDMA) channel access method for a single-hop wireless
network with one master and multiple slave nodes with TinyOS, and
then tested the performance in Cooja.

For TDMA method, the master is taking charge of assigning non-overlapping
time slots to the slaves that they can use to transmit packets to the master.
During the first slot of each epoch, the master broadcasts beacons to slaves
to do time synchronization, then in next slot, slaves try to join the epoch
and master will assign a unique slot for every slave transmitting data, thus
turning off the radios during unused slots will save energy.
