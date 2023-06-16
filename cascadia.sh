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
echo "export CASCADIA_CHAIN_ID=cascadia_6102-1" >> $HOME/.bash_profile
source $HOME/.bash_profile

# update
sudo apt update && sudo apt upgrade -y

# packages
sudo apt install curl build-essential git wget jq make gcc tmux chrony -y

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
cd $HOME && rm -rf cascadia
git clone https://github.com/cascadiafoundation/cascadia
cd cascadia
git checkout v0.1.2
make install

# config
cascadiad config chain-id $CASCADIA_CHAIN_ID
cascadiad config keyring-backend test

# init
cascadiad init $NODENAME --chain-id $CASCADIA_CHAIN_ID

# download genesis and addrbook
wget -O $HOME/.cascadiad/config/genesis.json "https://anode.team/Cascadia/test/genesis.json"
wget -O $HOME/.cascadiad/config/addrbook.json "https://anode.team/Cascadia/test/addrbook.json"

# set minimum gas price
sed -i -e "s|^minimum-gas-prices *=.*|minimum-gas-prices = \"0.025aCC\"|" $HOME/.cascadiad/config/app.toml

# set peers and seeds
SEEDS=""
PEERS="63cf1e7583eabf365856027815bc1491f2bc7939@65.108.2.41:60556,47aaa777fff4af6c03372fe9ff52e7afc3132f8c@34.125.205.40:26656,3b389873f999763d3f937f63f765f0948411e296@44.192.85.92:26656,b651ea2a0517e82c1a476e25966ab3de3159afe8@34.229.22.39:26656,a23ddb4174bd434eb134024a9531707d1a8fb7d1@207.246.124.228:26656"
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
curl https://snapshots1-testnet.nodejumper.io/cascadia-testnet/cascadia_6102-1_2023-06-16.tar.lz4 | lz4 -dc - | tar -xf - -C $HOME/.cascadiad

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
--chain-id=cascadia_6102-1 \
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
