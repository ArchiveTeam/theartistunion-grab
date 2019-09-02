#!/bin/sh -e

if ! sudo pip3 freeze | grep -q requests
then
  echo "Installing requests"
  if ! sudo pip3 install requests
  then
    exit 1
  fi
fi
