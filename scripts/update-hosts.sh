#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# Point the certificate's domain (default anton.com) at the public ALB in
# /etc/hosts, so https://anton.com reaches the ALB and the self-signed
# certificate's name matches.
#
# ALB IP addresses are not static (AWS replaces nodes when it scales), so this
# resolves them fresh every run - re-run it if the site stops answering.
#
# Usage:  sudo ./scripts/update-hosts.sh [domain] [alb-dns-name]
#         sudo ./scripts/update-hosts.sh --remove [domain]
# Without alb-dns-name it is looked up with the AWS CLI (needs credentials -
# run the lookup first without sudo if your AWS profile is not root's):
#         ./scripts/update-hosts.sh anton.com "$(cd terraform/environments/dev && terraform output -raw alb_dns_name)"
# -----------------------------------------------------------------------------
set -euo pipefail

HOSTS=/etc/hosts
BEGIN="# >>> commit-hw (managed by scripts/update-hosts.sh)"
END="# <<< commit-hw"

remove_block() {
  # Writes /etc/hosts without our block to stdout.
  awk -v b="$BEGIN" -v e="$END" '$0==b{skip=1;next} $0==e{skip=0;next} !skip' "$HOSTS"
}

flush_dns() {
  if [[ "$(uname)" == "Darwin" ]]; then
    dscacheutil -flushcache || true
    killall -HUP mDNSResponder 2>/dev/null || true
  fi
}

if [[ "${1:-}" == "--remove" ]]; then
  [[ $EUID -eq 0 ]] || { echo "run with sudo" >&2; exit 1; }
  tmp=$(mktemp); remove_block > "$tmp"; cat "$tmp" > "$HOSTS"; rm -f "$tmp"
  flush_dns
  echo "Removed the commit-hw block from $HOSTS"
  exit 0
fi

DOMAIN="${1:-anton.com}"
ALB_DNS="${2:-}"

if [[ -z "$ALB_DNS" ]]; then
  ALB_DNS=$(aws elbv2 describe-load-balancers --region us-east-1 --names commit-hw-dev-alb \
    --query 'LoadBalancers[0].DNSName' --output text)
fi

IPS=$(dig +short A "$ALB_DNS" | grep -E '^[0-9]+(\.[0-9]+){3}$' | sort -u || true)
[[ -n "$IPS" ]] || { echo "could not resolve $ALB_DNS" >&2; exit 1; }

echo "ALB    : $ALB_DNS"
echo "IPs    : $(echo "$IPS" | tr '\n' ' ')"
echo "Domain : $DOMAIN"

if [[ $EUID -ne 0 ]]; then
  echo
  echo "Re-run with sudo to write $HOSTS:"
  echo "  sudo $0 $DOMAIN $ALB_DNS"
  exit 0
fi

[[ -f "$HOSTS.bak-commit-hw" ]] || cp "$HOSTS" "$HOSTS.bak-commit-hw"

tmp=$(mktemp)
{
  remove_block
  echo "$BEGIN"
  while read -r ip; do echo "$ip $DOMAIN"; done <<< "$IPS"
  echo "$END"
} > "$tmp"
cat "$tmp" > "$HOSTS"   # keep the original file's owner and permissions
rm -f "$tmp"
flush_dns

echo "Updated $HOSTS (backup: $HOSTS.bak-commit-hw). Test with:"
echo "  curl -k https://$DOMAIN/"
