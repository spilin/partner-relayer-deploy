#!/bin/sh

network=${1:-"mainnet"}
namePostfix="near"

if [ "${network}" = "testnet" ]; then
	namePostfix="testnet"
fi


if [ ! -d ./contrib ]; then
	echo "Run ./setup.sh from original git repository only!"
	exit 1
fi

mkdir near config database 2> /dev/null
mkdir near/data 2> /dev/null


if [ ! -f ./near/config.json ]; then
	echo Downloading default configuration.
	curl -sSf -o ./near/config.json https://files.deploy.aurora.dev/"${network}"/config.json
fi

if [ ! -f ./near/genesis.json ]; then
	echo Downloading genesis file.
	curl -sSf -o ./near/genesis.json.gz https://files.deploy.aurora.dev/"${network}"/genesis.json.gz
	echo Uncompressing genesis file.
	gzip -d ./near/genesis.json.gz
fi

if [ ! -f ./near/node_key.json ]; then
	echo Generating node_key.
	./contrib/nearkey node%."${namePostfix}" > ./near/node_key.json
fi

if [ ! -f ./near/validator_key.json ]; then
	echo Generating validator_key.
	./contrib/nearkey node%."${namePostfix}" > ./near/validator_key.json
fi

if [ ! -f ./config/relayer.json ]; then
	echo Generating relayer key.
	./contrib/nearkey relayer%."${namePostfix}" > ./config/relayer.json
	relayerName=$(cat ./config/relayer.json | grep account_id | cut -d\" -f4)
	sed "s/%%SIGNER%%/${relayerName}/" contrib/"${network}".yaml > ./config/"${network}".yaml
fi

if [ ! -f ./config/blacklist.yaml ]; then
	cp ./contrib/blacklist.yaml ./config/blacklist.yaml
fi

if [ -f ./near/data/CURRENT -a -f ./database/.version ]; then
        echo Setup complete
fi


latest=""
if [ ! -f .latest ]; then
        echo Initial
        latest=$(curl -sSf  https://snapshots.deploy.aurora.dev/snapshots/"${network}"-latest)
        echo "${latest}" > ".latest"
fi
latest=$(cat ".latest")

if [ ! -f ./database/.version ]; then
        echo Downloading database snapshot ${latest}
        finish=0
        while [ ${finish} -eq 0 ]; do
                echo Fetching... this can take some time...
                # curl -sSf https://snapshots.deploy.aurora.dev/158c1b69348fda67682197791/"${network}"-db-"${latest}"/data.tar?lastfile=$(tail -n1 "./database/.lastfile") | tar -xv -C ./database/ >> ./database/.lastfile 2> /dev/null
                curl -sSf https://spilin.s3.eu-west-1.amazonaws.com/database.tar | tar -xv -C ./database/ >> ./database/.lastfile 2> /dev/null
                if [ -f ./database/.version ]; then
                        finish=1
                fi
        done
fi

if [ ! -f ./near/data/CURRENT ]; then
        echo Downloading near chain snapshot
        finish=0
        while [ ${finish} -eq 0 ]; do
                echo Fetching... this can take some time...
                docker run --init --rm --name snapshot_downloader -v `pwd`/near/:/home/near:rw --entrypoint /usr/local/bin/download_snapshot.sh nearaurora/nearcore-"${network}":latest
                if [ -f ./near/data/CURRENT ]; then
                        finish=1
                fi
        done
fi
cp ./contrib/docker-compose.yaml-"${network}" docker-compose.yaml
cp ./contrib/start.sh start.sh
cp ./contrib/stop.sh stop.sh
docker compose build --build-arg env=mainnet --no-cache
# rm setup.sh
echo Setup Complete
./start.sh
