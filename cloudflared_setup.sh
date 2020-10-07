#!/bin/sh
# Script to setup cloudflare's amazing SSH tunnel on both the remote-
# as well as any local machines
# After installation, the 'local' machine can create a ssh-connection
# to the 'remote' machine by using the default ssh command.
#
# see: man ssh
# see: https://developers.cloudflare.com/argo-tunnel/


VERSION='0.1'
CLOUDFLARE_LIST_FILE='/etc/apt/sources.list.d/cloudflare-main.list'


# ############################################################################ #
# usage                                                                        #
# ############################################################################ #
if [ "$#" -lt 2 ] || [ "$#" -gt 3 ]
then
    echo "Cloudflare Daemon (cloudflared) setup v$VERSION" >&2
    echo "Usage:"                                          >&2
    echo "$0 [local|remote] [port=22] HOSTNAME"            >&2
    exit 1
fi

# ############################################################################ #
# sanitize & check arguments                                                   #
# ############################################################################ #
if [ "$#" -eq 2 ]
then
    env=$1
    port=22
    host=$2
else
    env=$1
    port=$2
    host=$3
fi

if ! [ "$env" = "remote" ] && ! [ "$env" = "local" ]
then
    echo "Unknown environment <$env> - expected one of [local,remote]" >&2
    exit 2
fi

# ############################################################################ #
# check if we've got all programs we need                                      #
# ############################################################################ #
num_missing=0
chkprg() {
    local prg=$1
    local pad=$2

    printf "Checking availability of <%s> ...%s " $prg $pad
    if ! command -v "$prg" > /dev/null
    then
        printf "not found!\n"
        num_missing=$(expr $num_missing + 1)
    else
        printf "ok.\n"
    fi
}

chkprg apt ............
chkprg apt-key ........
chkprg lsb_release ....
chkprg systemctl ......

[ $num_missing -gt 0 ]                                                 \
    && echo "$num_missing required program(s) not found. Aborting."    \
    && exit 2

unset -f chkprg
unset -f num_missing


# ############################################################################ #
# script proper                                                                #
# ############################################################################ #
echo ""
echo "Cloudflared configuration:"
echo "debian_release: $(lsb_release -sc)"
echo "hostname:       $host"
echo "ssh-port:       $port"
echo "environment:    $env"
echo ""
printf "Are the above settings correct? [yes/no] "
read -r answer

# exit if answer is anything but literal "yes"
[ "$answer" = "yes" ] || exit 0
unset -f answer

echo "Adding cloudflare debPkg to APT sources"
printf "deb http://pkg.cloudflare.com/ %s main" $(lsb_release -sc)     \
    | sudo tee "$CLOUDFLARE_LIST_FILE" 1>/dev/null                     \
                                                                       || exit 2

echo "Adding cloudflare GPG to APT"
curl -C - https://pkg.cloudflare.com/pubkey.gpg | sudo apt-key add -   || exit 2


echo "Updating APT and installing cloudflared"
sudo apt update && sudo apt install cloudflared                        || exit 2


# ############################################################################ #
# cloudflared configuration                                                    #
# ############################################################################ #
if [ "$env" = "remote" ]
then

    # ######################################################################## #
    # remote configuration                                                     #
    # ######################################################################## #
    root_home=$(sudo printenv HOME)
    cert_loc="$root_home/.cloudflared/cert.pem"
    if sudo test -f $cert_loc 
    then
        echo "Found existing certificate in $cert_loc"
        printf "Replace and continue? [yes/no] "
        read -r answer
        [ "$answer" = "yes" ] || exit 0
        unset -f answer

        sudo rm $cert_loc
    fi
    unset -f cert_loc

    echo "Authenticating cloudflared"
    sudo cloudflared tunnel login                                      || exit 2


    echo "Connecting remote machine to cloudflare"
    sudo mkdir -p /etc/cloudflared                                     || exit 2
    printf "hostname: %s\nurl: %s\nlogfile: %s\n"                      \
            "$host"                                                    \
            "ssh://localhost:$port"                                    \
            "/var/log/cloudflared.log"                                 \
        | sudo tee /etc/cloudflared/config.yml > /dev/null             || exit 2


    echo "Copying certificate"
    sudo mv "$cert_loc" /etc/cloudflared/                              || exit 2
    sudo rm -rf "$root_home/.cloudflared"                              || exit 2


    echo "Installing cloudflared systemd-service"
    sudo cloudflared service install                                   || exit 2

    echo "Restarting cloudflared"
    echo "  this might take up to a few minutes."
    sudo systemctl restart cloudflared                                 || exit 2

    unset -f root_home

else

    # ######################################################################## #
    # local configuration                                                      #
    # ######################################################################## #

    echo "Adding ssh-proxy for <$host> to ~/.ssh/config" 
    mkdir -p "$HOME/.ssh"                                              || exit 2
    printf "Host %s\n  ProxyCommand %s access ssh --hostname %%h\n"    \
            $host                                                      \
            $(command -v cloudflared)                                  \
        | tee -a "$HOME/.ssh/config" > /dev/null                       || exit 2

fi

echo "Done."

