#!/bin/bash
set -e

DOMAIN=${1:-108.61.215.240}

echo "Building"
go build .

echo "Copy binary to server"
rsync -arzP ./turfwar $DOMAIN:/tmp/turfwar

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
