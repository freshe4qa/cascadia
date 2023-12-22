#!/bin/bash

while true
do

# Logo

echo -e '\e[40m\e[91m'
echo -e '  ____                  _                    '
echo -e ' / ___|_ __ _   _ _ __ | |_ ___  _ __        '
echo -e '| |   |  __| | | |  _ \| __/ _ \|  _ \       '
echo -e '| |___| |  | |_| | |_) | || (_) | | | |      '
echo -e ' \____|_|   \__  |  __/ \__\___/|_| |_|      '
echo -e '            |___/|_|                         '
echo -e '\e[0m'

sleep 2

# Menu

PS3='Select an action: '
options=(
"Install"
"Create Wallet"
"Create Validator"
"Exit")
select opt in "${options[@]}"
do
case $opt in

"Install")
echo "============================================================"
echo "Install start"
echo "============================================================"

# set vars
if [ ! $NODENAME ]; then
	read -p "Enter node name: " NODENAME
	echo 'export NODENAME='$NODENAME >> $HOME/.bash_profile
fi
if [ ! $WALLET ]; then
	echo "export WALLET=wallet" >> $HOME/.bash_profile
fi
echo "export CASCADIA_CHAIN_ID=cascadia_11029-1" >> $HOME/.bash_profile
source $HOME/.bash_profile

# update
sudo apt update && sudo apt upgrade -y

# packages
apt install curl iptables build-essential git wget jq make gcc nano tmux htop nvme-cli pkg-config libssl-dev libleveldb-dev tar clang bsdmainutils ncdu unzip libleveldb-dev -y

# install go
if ! [ -x "$(command -v go)" ]; then
ver="1.20.3" && \
wget "https://golang.org/dl/go$ver.linux-amd64.tar.gz" && \
sudo rm -rf /usr/local/go && \
sudo tar -C /usr/local -xzf "go$ver.linux-amd64.tar.gz" && \
rm "go$ver.linux-amd64.tar.gz" && \
echo "export PATH=$PATH:/usr/local/go/bin:$HOME/go/bin" >> $HOME/.bash_profile && \
source $HOME/.bash_profile
fi

# download binary
curl -L https://github.com/CascadiaFoundation/cascadia/releases/download/v0.2.0/cascadiad -o cascadiad
chmod +x cascadiad
sudo mv cascadiad /usr/local/bin

# config
cascadiad config chain-id $CASCADIA_CHAIN_ID
cascadiad config keyring-backend test

# init
cascadiad init $NODENAME --chain-id $CASCADIA_CHAIN_ID

# download genesis and addrbook
curl -L https://raw.githubusercontent.com/CascadiaFoundation/chain-configuration/master/testnet/genesis.json -o ~/.cascadiad/config/genesis.json
curl -s https://snapshots-testnet.nodejumper.io/cascadia-testnet/addrbook.json > $HOME/.cascadiad/config/addrbook.json

# set minimum gas price
sed -i -e "s|^minimum-gas-prices *=.*|minimum-gas-prices = \"0.025aCC\"|" $HOME/.cascadiad/config/app.toml

# set peers and seeds
SEEDS=""
PEERS="0c96a6c328eb58d1467afff4130ab446c294108c@34.239.67.55:26656,af73a10430d389e7480ef01b10b763fe156a397d@65.109.56.215:49656,c3fbcfce187a3733f688a945f80499de087d32ed@37.120.189.81:40656,21ca2712116138429aed3d72422379397c53fa86@65.109.65.248:34656,37024590fce8bbfcb0d4de7220967b63b5824d14@95.216.10.232:22256"
sed -i -e "s/^seeds *=.*/seeds = \"$SEEDS\"/; s/^persistent_peers *=.*/persistent_peers = \"$PEERS\"/" $HOME/.cascadiad/config/config.toml

# disable indexing
indexer="null"
sed -i -e "s/^indexer *=.*/indexer = \"$indexer\"/" $HOME/.cascadiad/config/config.toml

# config pruning
pruning="custom"
pruning_keep_recent="100"
pruning_keep_every="0"
pruning_interval="10"
sed -i -e "s/^pruning *=.*/pruning = \"$pruning\"/" $HOME/.cascadiad/config/app.toml
sed -i -e "s/^pruning-keep-recent *=.*/pruning-keep-recent = \"$pruning_keep_recent\"/" $HOME/.cascadiad/config/app.toml
sed -i -e "s/^pruning-keep-every *=.*/pruning-keep-every = \"$pruning_keep_every\"/" $HOME/.cascadiad/config/app.toml
sed -i -e "s/^pruning-interval *=.*/pruning-interval = \"$pruning_interval\"/" $HOME/.cascadiad/config/app.toml
sed -i "s/snapshot-interval *=.*/snapshot-interval = 0/g" $HOME/.cascadiad/config/app.toml

# enable prometheus
sed -i -e "s/prometheus = false/prometheus = true/" $HOME/.cascadiad/config/config.toml

# create service
sudo tee /etc/systemd/system/cascadiad.service > /dev/null << EOF
[Unit]
Description=Cascadia Node
After=network-online.target
[Service]
User=$USER
ExecStart=$(which cascadiad) start
Restart=on-failure
RestartSec=10
LimitNOFILE=10000
[Install]
WantedBy=multi-user.target
EOF

# reset
cascadiad tendermint unsafe-reset-all --home $HOME/.cascadiad --keep-addr-book 
curl https://snapshots-testnet.nodejumper.io/cascadia-testnet/cascadia-testnet_latest.tar.lz4 | lz4 -dc - | tar -xf - -C $HOME/.cascadiad

# start service
sudo systemctl daemon-reload
sudo systemctl enable cascadiad
sudo systemctl restart cascadiad

break
;;

"Create Wallet")
cascadiad keys add $WALLET
echo "============================================================"
echo "Save address and mnemonic"
echo "============================================================"
CASCADIA_WALLET_ADDRESS=$(cascadiad keys show $WALLET -a)
CASCADIA_VALOPER_ADDRESS=$(cascadiad keys show $WALLET --bech val -a)
echo 'export CASCADIA_WALLET_ADDRESS='${CASCADIA_WALLET_ADDRESS} >> $HOME/.bash_profile
echo 'export CASCADIA_VALOPER_ADDRESS='${CASCADIA_VALOPER_ADDRESS} >> $HOME/.bash_profile
source $HOME/.bash_profile

break
;;

"Create Validator")
cascadiad tx staking create-validator \
--amount=1000000aCC \
--pubkey=$(cascadiad tendermint show-validator) \
--moniker="$NODENAME" \
--chain-id=cascadia_11029-1 \
--commission-rate=0.1 \
--commission-max-rate=0.2 \
--commission-max-change-rate=0.05 \
--min-self-delegation=1 \
--from=wallet \
--gas-prices="7aCC"
-y

break
;;

"Exit")
exit
;;
*) echo "invalid option $REPLY";;
esac
done
done
