#!/bin/bash
# damage-control.sh — Safeguard Guard
# Blocks or escalates destructive shell commands.
# Input: JSON on stdin. Output: BLOCK:<reason> | ASK:<reason> | empty (allow).

INPUT=$(cat)
. "$(dirname "$0")/../lib/json-field.sh"

CMD=$(json_field "command" "$INPUT")
[ -z "$CMD" ] && exit 0

CMD_LOWER=$(printf '%s' "$CMD" | tr 'A-Z' 'a-z')

deny()  { printf 'BLOCK:[safeguard:damage-control] BLOCKED: %s' "$1"; exit 0; }
ask()   { printf 'ASK:[safeguard:damage-control] %s' "$1"; exit 0; }

# ============================================================
# DENY — hard block, zero legitimate AI use
# ============================================================

# Filesystem nukes: rm with recursive flag on dangerous targets
_dc_has_recursive_rm=false
case " $CMD " in
  *" rm "*|*";rm "*|*"&&rm "*|*"||rm "*|*"| rm "*)
    _dc_flags=$(printf '%s\n' "$CMD" | awk '
      BEGIN { found=0 }
      {
        for (i=1; i<=NF; i++) {
          if ($i == "rm") { found=1; continue }
          if (found && substr($i,1,1) == "-") { printf "%s ", $i; continue }
          if (found) { found=0 }
        }
      }')
    case "$_dc_flags" in
      *[rR]*) _dc_has_recursive_rm=true ;;
    esac
    ;;
esac

if [ "$_dc_has_recursive_rm" = "true" ]; then
  case "$CMD" in
    *" /"|*" /"*|*" /bin"*|*" /etc"*|*" /usr"*|*" /var"*|*" /home"*|*" /tmp"*|*" /opt"*|*" /root"*)
      deny "recursive rm of absolute system path" ;;
    *" ~"|*" ~"*|*" \$HOME"*|*" \${HOME}"*)
      deny "recursive rm of home directory" ;;
    *" ."|*" ./") deny "recursive rm of current directory" ;;
    *" *"|*" */"*) deny "recursive rm of glob wildcard" ;;
  esac
fi

case "$CMD" in
  *mkfs*) deny "filesystem format operation" ;;
  *dd\ *of=/dev/*) deny "raw device write" ;;
  *fdisk\ *) deny "disk partition operation" ;;
  *parted\ *) deny "disk partition operation" ;;
  *wipefs\ *) deny "filesystem signature wipe" ;;
  *mdadm\ *--zero-superblock*) deny "RAID superblock wipe" ;;
esac

case "$CMD" in
  *kill\ -9\ -1*|*killall\ -9*) deny "kill all processes" ;;
esac

case "$CMD" in
  *chmod\ 777\ /*|*chmod\ -R\ 777*) deny "world-writable permissions" ;;
  *chown\ -R\ root\ /*|*chown\ root:root\ /*) deny "recursive chown to root on system path" ;;
esac

case "$CMD" in
  *shutdown*|*reboot*|*init\ 0*|*init\ 6*|*poweroff*) deny "system power operation" ;;
  *systemctl\ poweroff*|*systemctl\ reboot*|*systemctl\ halt*) deny "system power operation (systemctl)" ;;
esac

case "$CMD" in
  *:\(\)\{*\|*:\&*\}*) deny "fork bomb" ;;
esac

# ============================================================
# ASK — dangerous but sometimes intentional
# ============================================================

case "$CMD" in
  *git\ reset\ --hard*) ask "git reset --hard (discards uncommitted changes)" ;;
  *git\ clean\ *-f*|*git\ clean\ *-d*f*|*git\ clean\ *-f*d*) ask "git clean -f (removes untracked files)" ;;
  *git\ stash\ clear*) ask "git stash clear (destroys all stashes)" ;;
  *git\ stash\ drop*) ask "git stash drop (destroys a stash)" ;;
  *git\ filter-branch*) ask "git filter-branch (rewrites history)" ;;
  *git\ reflog\ expire*) ask "git reflog expire (removes reflog entries)" ;;
  *git\ checkout\ --\ .|*git\ checkout\ --\ .\ *) ask "git checkout -- . (discards all working changes)" ;;
  *git\ restore\ .|*git\ restore\ .\ *) ask "git restore . (discards all working changes)" ;;
  *git\ branch\ -D*) ask "git branch -D (force-deletes branch)" ;;
esac

case "$CMD" in
  *git\ push*--force-with-lease*) ;;
  *git\ push*--force*|*git\ push*\ -f\ *|*git\ push*\ -f$)
    ask "git push --force (consider --force-with-lease instead)" ;;
esac

case "$CMD" in
  *docker\ system\ prune*) ask "docker system prune (removes all unused data)" ;;
  *docker\ rm\ -f*\$\(*|*docker\ rm\ -f*\`*) ask "docker rm -f with subshell (bulk container removal)" ;;
  *docker\ rmi\ -f*\$\(*|*docker\ rmi\ -f*\`*) ask "docker rmi -f with subshell (bulk image removal)" ;;
  *docker\ volume\ prune*) ask "docker volume prune (removes all unused volumes)" ;;
esac

case "$CMD" in
  *terraform\ destroy*) ask "terraform destroy" ;;
  *pulumi\ destroy*) ask "pulumi destroy" ;;
  *aws\ s3\ rm\ --recursive*|*aws\ s3\ rb*) ask "AWS S3 bulk delete" ;;
  *aws\ ec2\ terminate-instances*) ask "AWS EC2 terminate instances" ;;
  *kubectl\ delete\ namespace*|*kubectl\ delete\ all\ --all*) ask "kubectl bulk delete" ;;
esac

case "$CMD" in
  *gcloud\ *\ delete\ *|*gcloud\ *\ delete$) ask "gcloud delete operation" ;;
esac

case "$CMD_LOWER" in
  *drop\ table*|*drop\ database*|*drop\ schema*) ask "SQL DROP operation" ;;
  *truncate\ table*|*truncate\ *) ask "SQL TRUNCATE operation" ;;
esac

if printf '%s' "$CMD_LOWER" | grep -q 'delete[[:space:]]\+from'; then
  if ! printf '%s' "$CMD_LOWER" | grep -q 'where'; then
    ask "SQL DELETE without WHERE clause"
  fi
fi

case "$CMD_LOWER" in
  *redis-cli*flushall*|*redis-cli*flushdb*) ask "Redis FLUSH (destroys all data)" ;;
esac

case "$CMD_LOWER" in
  *mongo*dropdatabase*|*mongo*dropcollection*|*mongosh*dropdatabase*) ask "MongoDB drop operation" ;;
esac

# --- Secrets Management ---
case "$CMD" in
  *vault\ kv\ destroy*|*vault\ kv\ metadata-delete*) ask "Vault secret destruction" ;;
  *vault\ secrets\ disable*) ask "Vault secrets engine disable (data loss)" ;;
  *vault\ token\ revoke*) ask "Vault token revocation" ;;
  *aws\ secretsmanager\ delete-secret*) ask "AWS Secrets Manager delete" ;;
  *aws\ ssm\ delete-parameter*) ask "AWS SSM parameter delete" ;;
esac

# --- CI/CD ---
case "$CMD" in
  *gh\ secret\ delete*|*gh\ secret\ remove*) ask "GitHub secret deletion" ;;
  *gh\ variable\ delete*|*gh\ variable\ remove*) ask "GitHub variable deletion" ;;
  *gh\ workflow\ disable*) ask "GitHub workflow disable" ;;
  *glab\ variable\ delete*) ask "GitLab variable deletion" ;;
  *glab\ ci\ delete*) ask "GitLab CI artifact/pipeline deletion" ;;
esac

# --- Extended Terraform ---
case "$CMD" in
  *terraform\ state\ rm*) ask "terraform state rm (removes resource from state)" ;;
  *terraform\ state\ mv*) ask "terraform state mv (moves resource in state)" ;;
  *terraform\ force-unlock*) ask "terraform force-unlock (breaks state lock)" ;;
  *terraform\ apply*-auto-approve*) ask "terraform apply -auto-approve (no review)" ;;
esac

# --- Extended Docker ---
case "$CMD" in
  *docker\ compose\ down*-v*|*docker\ compose\ down*--volumes*) ask "docker compose down -v (destroys volumes)" ;;
  *docker\ compose\ down*--rmi*) ask "docker compose down --rmi (removes images)" ;;
  *docker\ stop*\$\(*|*docker\ stop*\`*) ask "docker stop with subshell (bulk stop)" ;;
  *docker\ kill*\$\(*|*docker\ kill*\`*) ask "docker kill with subshell (bulk kill)" ;;
esac

# --- Extended Kubernetes / Helm ---
case "$CMD" in
  *kubectl\ delete*--all*) ask "kubectl delete --all (bulk resource deletion)" ;;
  *helm\ uninstall*|*helm\ delete*) ask "Helm release deletion" ;;
esac

# --- Cloud Storage ---
case "$CMD" in
  *gsutil\ rm\ -r*|*gsutil\ rb*) ask "GCS bucket/object deletion" ;;
  *gcloud\ storage\ buckets\ delete*|*gcloud\ storage\ rm*) ask "GCS storage deletion" ;;
  *az\ storage\ container\ delete*|*az\ storage\ blob\ delete-batch*) ask "Azure storage deletion" ;;
  *aws\ s3api\ delete-bucket*|*aws\ s3api\ delete-objects*) ask "AWS S3 API deletion" ;;
  *aws\ s3\ sync*--delete*) ask "AWS S3 sync --delete (removes target files)" ;;
esac

# --- Database CLI tools ---
case "$CMD" in
  *dropdb\ *) ask "PostgreSQL dropdb (destroys database)" ;;
  *dropuser\ *) ask "PostgreSQL dropuser (removes user)" ;;
  *mysqladmin\ *drop*) ask "MySQL database drop" ;;
esac

# --- Package Managers ---
case "$CMD" in
  *npm\ unpublish*) ask "npm unpublish (removes package from registry)" ;;
  *cargo\ yank*) ask "cargo yank (removes crate version)" ;;
esac

# --- Remote Operations ---
case "$CMD" in
  *rsync*--delete*|*rsync*--del\ *|*rsync*--del$) ask "rsync --delete (removes files at destination)" ;;
  *ssh\ *rm\ -rf*|*ssh\ *rm\ -r\ *) ask "remote rm -rf via SSH" ;;
  *ssh\ *git\ reset\ --hard*) ask "remote git reset --hard via SSH" ;;
esac

exit 0
