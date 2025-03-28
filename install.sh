#!/bin/bash

set -e  # Dừng ngay nếu có lỗi

random() {
    tr </dev/urandom -dc A-Za-z0-9 | head -c5
    echo
}

array=(1 2 3 4 5 6 7 8 9 0 a b c d e f)
gen64() {
    ip64() {
        echo "${array[$RANDOM % 16]}${array[$RANDOM % 16]}${array[$RANDOM % 16]}${array[$RANDOM % 16]}"
    }
    echo "$1:$(ip64):$(ip64):$(ip64):$(ip64)"
}

install_packages() {
    echo "Detecting OS and installing required packages..."
    if [[ -f /etc/debian_version ]]; then
        apt update && apt install -y gcc make net-tools curl unzip iptables
    elif [[ -f /etc/redhat-release ]]; then
        yum install -y gcc make net-tools curl unzip iptables
    else
        echo "Unsupported OS. Please use Ubuntu, Debian, CentOS, or RHEL."
        exit 1
    fi
}

install_3proxy() {
    echo "Installing 3proxy..."
    wget -qO- https://github.com/z3APA3A/3proxy/archive/refs/tags/0.9.4.tar.gz | tar -xz
    cd 3proxy-0.9.4
    make -f Makefile.Linux
    mkdir -p /usr/local/etc/3proxy/{bin,logs,stat}
    cp src/3proxy /usr/local/etc/3proxy/bin/
    cd ..
    rm -rf 3proxy-0.9.4
}

gen_3proxy_config() {
    cat <<EOF >/usr/local/etc/3proxy/3proxy.cfg
daemon
maxconn 1000
nscache 65536
timeouts 1 5 30 60 180 1800 15 60
setgid 65535
setuid 65535
flush
auth strong

users $(awk -F "/" '{print $1 ":CL:" $2 " "}' ${WORKDATA})

$(awk -F "/" '{print "auth strong\n" \
"allow " $1 "\n" \
"proxy -6 -n -a -p" $4 " -i" $3 " -e"$5"\n" \
"flush\n"}' ${WORKDATA})
EOF
}

create_systemd_service() {
    cat <<EOF >/etc/systemd/system/3proxy.service
[Unit]
Description=3proxy Proxy Server
After=network.target

[Service]
ExecStart=/usr/local/etc/3proxy/bin/3proxy /usr/local/etc/3proxy/3proxy.cfg
Restart=always
User=nobody
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
EOF
    systemctl enable 3proxy
    systemctl start 3proxy
}

gen_data() {
    seq $FIRST_PORT $LAST_PORT | while read port; do
        echo "usr$(random)/pass$(random)/$IP4/$port/$(gen64 $IP6)"
    done
}

gen_iptables() {
    awk -F "/" '{print "iptables -I INPUT -p tcp --dport " $4 " -m state --state NEW -j ACCEPT"}' ${WORKDATA} >/etc/iptables.rules
    iptables-restore < /etc/iptables.rules
    iptables-save >/etc/iptables.conf
}

gen_ip6addr() {
    awk -F "/" '{print "ip -6 addr add " $5 "/64 dev eth0"}' ${WORKDATA} >/etc/netplan/ipv6-add.sh
    chmod +x /etc/netplan/ipv6-add.sh
    bash /etc/netplan/ipv6-add.sh
}

upload_proxy() {
    local PASS=$(random)
    zip --password $PASS proxy.zip proxy.txt
    URL=$(curl -s --upload-file proxy.zip https://transfer.sh/proxy.zip)

    echo "Proxy is ready! Format: IP:PORT:LOGIN:PASS"
    echo "Download zip archive from: ${URL}"
    echo "Password: ${PASS}"
}

### Main script execution ###
echo "Installing dependencies..."
install_packages

WORKDIR="/home/proxy-installer"
WORKDATA="${WORKDIR}/data.txt"
mkdir -p $WORKDIR && cd $_

IP4=$(curl -4 -s icanhazip.com)
IP6=$(curl -6 -s icanhazip.com | cut -f1-4 -d':')

echo "Detected IPv4 = ${IP4}, IPv6 Subnet = ${IP6}"
echo "Enter the number of proxies to create (e.g., 500):"
read COUNT

FIRST_PORT=10000
LAST_PORT=$(($FIRST_PORT + $COUNT))

echo "Generating proxy data..."
gen_data >$WORKDIR/data.txt
gen_iptables
gen_ip6addr
gen_3proxy_config
create_systemd_service

echo "Generating proxy list for users..."
awk -F "/" '{print $3 ":" $4 ":" $1 ":" $2 }' ${WORKDATA} >proxy.txt

upload_proxy
