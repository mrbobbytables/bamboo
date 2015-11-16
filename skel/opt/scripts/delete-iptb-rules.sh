#!/bin/bash
#cleanup in case container was killed while updating
iptables -D INPUT -p tcp -m multiport --dports 80,443 --syn -j DROP
