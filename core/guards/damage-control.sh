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
  *git\ checkout\ --\ .*) ask "git checkout -- . (discards all working changes)" ;;
  *git\ restore\ .*) ask "git restore . (discards all working changes)" ;;
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

exit 0
