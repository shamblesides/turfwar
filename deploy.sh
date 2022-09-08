#!/bin/bash
set -e

DOMAIN=${1:-ipv4.games}

echo "Building"
make

echo "Copy binary to server"
scp ./server.com $DOMAIN:/tmp/turfwar

echo "Assimilate cosmopolitan binary"
ssh $DOMAIN /tmp/turfwar --assimilate

echo "Stop systemd service"
ssh $DOMAIN sudo systemctl stop turfwar.service

echo "Replacing old binary"
ssh $DOMAIN sudo cp /tmp/turfwar /srv/turfwar

echo "Setting low-port-binding permissions on binary"
ssh $DOMAIN sudo setcap CAP_NET_BIND_SERVICE=+eip /srv/turfwar

echo "Enabling and starting systemd service"
ssh $DOMAIN sudo systemctl enable turfwar.service
ssh $DOMAIN sudo systemctl restart turfwar.service

echo "OK!"
