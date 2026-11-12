#!/usr/bin/env bash
# runall.sh - runs Portfolios 1-5 in your own Codespace, commits each one, collects results.
#   bash runall.sh        runs P1 to P5
#   bash runall.sh 3      resumes from P3
START="${1:-1}"
REPO="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "$REPO" || exit 1

# 1. find the kit (re-unzip the FIXED zip if the Codespace lost ~/kit)
KIT="$(find "$HOME/kit" -maxdepth 2 -type d -name advanced-database-portfolio 2>/dev/null | head -1)"
if [ -z "$KIT" ]; then
  Z="$(ls "$REPO" | grep FIXED | grep zip | head -1)"
  [ -n "$Z" ] || { echo "!!! Cannot find the FIXED zip in $REPO. Drag it in again."; exit 1; }
  mkdir -p "$HOME/kit"; unzip -oq "$REPO/$Z" -d "$HOME/kit"
  KIT="$HOME/kit/advanced-database-portfolio"
fi
echo "Kit: $KIT"
cp -f "$KIT/collect_results.sh" "$REPO/collect_results.sh"

# 2. services (a sleeping Codespace stops them)
sudo pg_ctlcluster 16 main start 2>/dev/null || true
if ! psql -h /var/run/postgresql -U freshfold -d freshfold -c 'SELECT 1' >/dev/null 2>&1; then
  echo "Database not ready - running setup.sh ..."
  bash "$KIT/setup.sh" || { echo "!!! setup.sh FAILED - send Joseph the error above"; exit 1; }
fi
if ! pgrep -x mongod >/dev/null; then
  sudo mkdir -p /data/db /var/log/mongodb
  sudo mongod --fork --logpath /var/log/mongodb/mongod.log --dbpath /data/db --bind_ip 127.0.0.1 --port 27017 >/dev/null
  sleep 3
fi
mongosh --quiet --eval 'db.runCommand({ping:1}).ok' 2>/dev/null | grep -q 1 || { echo "!!! MongoDB not answering - send Joseph this message"; exit 1; }

# 3. python libraries (fallback chain)
if ! python3 -c 'import psycopg2, pymongo, faker' 2>/dev/null; then
  P="pymongo psycopg2-binary Faker"
  python3 -m pip install -q $P || python3 -m pip install -q --user $P || python3 -m pip install -q --break-system-packages $P \
   || python3 -m pip install -q --user --break-system-packages $P || sudo apt-get install -y python3-psycopg2 python3-pymongo python3-faker
  python3 -c 'import psycopg2, pymongo, faker' || { echo "!!! Python libraries missing - send Joseph this message"; exit 1; }
fi

# 4. the five portfolios (explicit list, no wildcards)
DIRS=(portfolio-1-database-design portfolio-2-query-optimisation portfolio-3-transactions-concurrency portfolio-4-nosql portfolio-5-distributed-cloud)
MSG=("Portfolio 1: database design" "Portfolio 2: query optimisation" "Portfolio 3: transactions and concurrency" "Portfolio 4: MongoDB" "Portfolio 5: partitioning and replica")
mkdir -p docs; cp -rf "$KIT/docs/." docs/ 2>/dev/null; cp -f "$KIT/README.md" "$KIT/CHANGES.md" . 2>/dev/null
for i in 0 1 2 3 4; do
  N=$((i+1)); D="${DIRS[$i]}"
  [ "$N" -lt "$START" ] && continue
  echo; echo "################ P$N : $D ################"
  mkdir -p "$REPO/$D"; cp -rf "$KIT/$D/." "$REPO/$D/"
  ( cd "$REPO/$D" && set -o pipefail && bash "run_p$N.sh" 2>&1 | tee "p${N}_output.log" )
  if [ "${PIPESTATUS[0]}" -ne 0 ]; then
    echo "!!! P$N FAILED - send Joseph the file $D/p${N}_output.log (open it and copy all the text)"
    exit 1
  fi
  git add -A >/dev/null 2>&1; git commit -qm "${MSG[$i]}: code and real run output" >/dev/null 2>&1
  git push -q 2>/dev/null || echo "(push skipped - run: git push)"
done

# 5. results
bash "$REPO/collect_results.sh"
git add -A >/dev/null 2>&1; git commit -qm "Add collected results" >/dev/null 2>&1; git push -q 2>/dev/null
(code my_results.txt 2>/dev/null || true)
echo; echo "ALL DONE. Open my_results.txt, press Ctrl+A, Ctrl+C and paste it to Joseph."
