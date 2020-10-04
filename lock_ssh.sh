#!/bin/sh

sudo cp /etc/ssh/sshd_config /etc/ssh/sshd_config.bak

cat /etc/ssh/sshd_config \
    | sed -e "s/\s*#*\s*PasswordAuthentication\s*yes.*/PasswordAuthentication no/"                   \
    | sed -e "s/\s*#*\s*PermitRootLogin\s*yes.*/PermitRootLogin no/"                                 \
    | sed -e "s/\s*#*\s*ChallengeResponseAuthentication\s*yes.*/ChallengeResponseAuthentication no/" \
    | sed -e "s/\s*#*\s*UsePAM\s*yes.*/UsePAM no/"                                                   \
    > $HOME/sshd_config

sudo mv $HOME/sshd_config /etc/ssh/sshd_config
