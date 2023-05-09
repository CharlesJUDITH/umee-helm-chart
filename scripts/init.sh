#!/bin/bash
set -x

#Install utils
apt update && apt -y --no-install-recommends install ca-certificates curl jq > /dev/null 2>&1

# fail fast should there be a problem installing curl / jq packages
type curl || exit 1
type jq || exit 1

# If Address book is enabled, download it
if [ "$UMEE_ADDRBOOK_ENABLED" == true ]; then
  curl -s "$UMEE_ADDRBOOK_URL" > "$UMEE_HOME/config/addrbook.json"
fi

#Check if Home data exists, if not create it.
if [ ! -d "$UMEE_HOME/data" ]
then
mkdir -p $UMEE_HOME/data
# Init the chain
/usr/bin/umeed init --chain-id "$UMEE_CHAIN_ID" "$UMEE_MONIKER"

# If the node is a validator, do tx to create the validator
# Make sure the Validator has fully synced before running 
# if $UMEE_VALIDATOR; then
#   umeed tx staking create-validator \
#     --from "<key-name>" \
#     --amount "1000000uhuahua" \
#     --pubkey "$(umeed tendermint show-validator)" \
#     --chain-id "$UMEE_CHAIN_ID" \
#     --moniker "$UMEE_MONIKER" \
#     --commission-max-change-rate 0.01 \
#     --commission-max-rate 0.20 \
#     --commission-rate 0.10 \
#     --min-self-delegation 1 \
#     --details "<details>" \
#     --security-contact "<contact>" \
#     --website "<website>" \
#     --gas-prices "1uhuahua"
# fi

cd "$UMEE_HOME/data" || exit
curl -s "$UMEE_NET/genesis.json" > "$UMEE_HOME/config/genesis.json"
if [ "$UMEE_STATESYNC_ENABLE" == true ]; then
  echo "state-sync is enabled, figure the right trust height & derive its hash"

  export SNAP_RPC1="{{ .Values.state_sync.rpc1 }}"
  export SNAP_RPC2="{{ .Values.state_sync.rpc2 }}"

  LATEST_HEIGHT=$(curl -Ls "$SNAP_RPC1/block" | jq -r .result.block.header.height)
  HEIGHT_OFFSET="{{ .Values.state_sync.height_offset }}"
  BLOCK_HEIGHT=$((LATEST_HEIGHT - HEIGHT_OFFSET))
  TRUST_HASH=$(curl -Ls "$SNAP_RPC1/block?height=$BLOCK_HEIGHT" | jq -r .result.block_id.hash)

  echo "TRUST HEIGHT: $BLOCK_HEIGHT"
  echo "TRUST HASH: $TRUST_HASH"

  export UMEE_STATESYNC_TRUST_HEIGHT=$BLOCK_HEIGHT
  export UMEE_STATESYNC_TRUST_HASH=$TRUST_HASH

else
  if [ "$UMEE_CHAIN_ID" == "umee-1" ]; then
    apt -y --no-install-recommends install aria2 lz4 liblz4-tool wget > /dev/null 2>&1
    case "$SNAPSHOT_PROVIDER" in

      "polkachu")
        SNAPSHOT_URL=$(curl -s https://polkachu.com/tendermint_snapshots/umee | grep tar.lz4 | head -n1 | grep -io '<a href=['"'"'"][^"'"'"']*['"'"'"]' |   sed -e 's/^<a href=["'"'"']//i' -e 's/["'"'"']$//i')
        echo "Using latest Polkachu blockchain snapshot, $SNAPSHOT_URL"
        aria2c --out=snapshot.tar.lz4 --summary-interval 15 --check-certificate=false --max-tries=99 --retry-wait=5 --always-resume=true --max-file-not-found=99 --conditional-get=true -s 4 -x 4 -k 1M -j 1 "$SNAPSHOT_URL"
        lz4 -c -d snapshot.tar.lz4 | tar -x -C "$UMEE_HOME"
        rm -f snapshot.tar.lz4
        ;;
      "autostake")
	SNAP_NAME=$(curl -s http://snapshots.autostake.net/umee-1/ | egrep -o ">umee-1-.*.tar.lz4" | tr -d ">" | tail -1)
	wget -O - http://snapshots.autostake.net/umee-1/$SNAP_NAME | lz4 -d | tar -xf - -C "$UMEE_HOME"
	;;

    esac

  fi
fi
else
  echo "Found Umee data folder!"
  cd "$UMEE_HOME/data" || exit
fi

if [[ $UMEE_DEBUG == "true" ]]; then sleep 5000; fi
