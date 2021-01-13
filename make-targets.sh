#!/usr/bin/env nix-shell
#!nix-shell -i bash -I nixpkgs=channel:nixos-unstable-small -p jq

set -eux
set -o pipefail

scratch=$(mktemp -d -t tmp.XXXXXXXXXX)
function finish {
	  rm -rf "$scratch"
  }
trap finish EXIT


machines() (
  cd "$(dirname "$0")/terraform"
  nix-shell --run "set -o pipefail; cd base && terraform init && terraform output -json | jq .deploy_targets.value" \
	  | jq -cr '. as $input | keys | map(. as $name | { key: $name, value: $input[$name]}) | .[]'
)

mkdir "$scratch/machines"

networkentry() (
  name=$1
  ip=$2

  cat <<EOF
  "$name" = {
    deployment = {
      targetHost = "$ip";
      targetUser = "root";
      substituteOnDestination = true;
    };
    imports = [
      ../nixops/modules
      ./machines/$name.expr.nix
      ./machines/$name.system.nix
    ];
  };
EOF
)

cat <<EOF > "$scratch/default.nix"
{
  network = {
    pkgs = import <nixpkgs> {};
    nixConfig = {
      builders = "";
      experimental-features = "nix-command";
    };
  };

EOF

machines | while read machine; do
   (
        name="$(jq -r .key <<<"$machine")"
        ip=$(jq -r .value.ip <<<"$machine")
        jq -r .value.expression <<<"$machine"
        jq -r .value.expression <<<"$machine" > "$scratch/machines/${name}.expr.nix"
        if ssh -o BatchMode=yes -o IdentitiesOnly=yes -i ./deploy.key "root@$ip" -- cat /etc/nixos/packet/system.nix > "$scratch/machines/${name}.system.nix"; then
          networkentry "$name" "$ip" >> "$scratch/default.nix"
        fi
   ) < /dev/null
done

echo "}" >> "$scratch/default.nix"

git rm -rf ./morph-network
rm -rf ./morph-network

mv "$scratch" ./morph-network
git add morph-network

