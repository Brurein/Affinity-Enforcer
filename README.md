# Affinity-Enforcer
A powershell script to enforce CPU core affinity and process priority levels.

 My usecase for this tool is to ensure QoS on a multisession Azure Virtual Desktop, which runs HPC software for teaching. I don't care if it affects performance, just so long as windows doesn't crash, chrome still runs etc...
 
 The idea behind this script is that you shunt essential services onto lower cores and more demanding software is forced onto higher cores. This means there's always cpu capacity to service the user experience.
 
 The target platform for this script is 128gb/32c vm's, so there's plenty of cores, this script will liekly be less effective on machines with less resources available. It also doesn't care about  E/P cores on newer intel platforms.


