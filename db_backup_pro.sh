#!/usr/bin/env bash
# db_backup_pro.sh — Backup otimizado de MySQL/MariaDB e PostgreSQL (com email HTML opcional)
# Autor: Thiago Motta Massensini | suporte@hextec.com.br | Licença: MIT
#
# Diferença desta versão:
# - Envio de log por e-mail com suporte a HTML: defina SEND_LOG=true e SEND_LOG_FORMAT=html
# - Cabeçalhos MIME corretos para HTML usando msmtp
#
set -Eeuo pipefail

DB_TYPE="${DB_TYPE:-}"
if [[ -z "${DB_TYPE}" ]]; then
  echo "[!] DB_TYPE não definido. Use DB_TYPE=mysql ou DB_TYPE=postgres"
  exit 1
fi
case "${DB_TYPE}" in mysql|postgres) ;; *) echo "[!] DB_TYPE inválido: ${DB_TYPE}"; exit 1;; esac

BACKUP_DIR="${BACKUP_DIR:-/backup/db}"
LOG_DIR="${LOG_DIR:-/var/log/db-backup}"
RETENTION_DAYS="${RETENTION_DAYS:-10}"
COMP="${COMP:-auto}"
ENV_FILE="${ENV_FILE:-/etc/db_backup.env}"

MYSQL_HOST="${MYSQL_HOST:-127.0.0.1}"
MYSQL_PORT="${MYSQL_PORT:-3306}"
MYSQL_USER="${MYSQL_USER:-root}"
MYSQL_PASSWORD="${MYSQL_PASSWORD:-}"

PGHOST="${PGHOST:-127.0.0.1}"
PGPORT="${PGPORT:-5432}"
PGUSER="${PGUSER:-postgres}"
PGPASSWORD="${PGPASSWORD:-${PGPASSWORD:-}}"
PGDATABASE="${PGDATABASE:-postgres}"

SEND_LOG="${SEND_LOG:-false}"
SEND_LOG_FORMAT="${SEND_LOG_FORMAT:-text}"   # text|html
EMAIL="${EMAIL:-}"
FROM="${FROM:-}"

if [[ -f "$ENV_FILE" ]]; then source "$ENV_FILE"; fi

DATE="$(date +%F-%H%M%S)"
HOST="$(hostname)"
RUN_BASE="${BACKUP_DIR%/}/${HOST}/${DB_TYPE}"
RUN_DIR="${RUN_BASE}/${DATE}"
mkdir -p "$RUN_DIR" "$LOG_DIR" "$RUN_BASE"

LOG_FILE="${LOG_DIR%/}/backup_${DB_TYPE}_${HOST}_${DATE}.log"
exec > >(tee -a "$LOG_FILE") 2>&1

START_TS=$(date +%s)
echo "[=] Início: $(date '+%F %T') | Tipo: ${DB_TYPE} | Host: ${HOST}"

finish() {
  local code=$?
  local end_ts=$(date +%s)
  local dur=$((end_ts - START_TS))
  printf "\n[=] Fim: %s | Duração: %02d:%02d:%02d | Código: %d\n" \
    "$(date '+%F %T')" $((dur/3600)) $(((dur%3600)/60)) $((dur%60)) "$code"
  exit "$code"
}
trap finish EXIT

have() { command -v "$1" >/dev/null 2>&1; }

choose_comp() {
  local c="$COMP"
  if [[ "$c" == "auto" ]]; then
    if have zstd; then echo "zstd"; return; fi
    if have pigz; then echo "pigz"; return; fi
    if have gzip; then echo "gzip"; return; fi
    echo "none"; return
  else
    echo "$c"
  fi
}

fmt_bytes() { numfmt --to=iec --suffix=B --padding=7 "${1:-0}" 2>/dev/null || echo "${1:-0}B"; }

has_flag_mysql() { mysqldump --help 2>&1 | grep -q "$1"; }
mysql_exec() {
  mysql --host="$MYSQL_HOST" --port="$MYSQL_PORT" --user="$MYSQL_USER" \
        ${MYSQL_PASSWORD:+--password="$MYSQL_PASSWORD"} "$@"
}
mysqldump_exec() {
  mysqldump --host="$MYSQL_HOST" --port="$MYSQL_PORT" --user="$MYSQL_USER" \
            ${MYSQL_PASSWORD:+--password="$MYSQL_PASSWORD"} "$@"
}
psql_exec()    { PGPASSWORD="$PGPASSWORD" psql     --host="$PGHOST" --port="$PGPORT" --username="$PGUSER" --dbname="$PGDATABASE" "$@"; }
pg_dump_exec() { PGPASSWORD="$PGPASSWORD" pg_dump  --host="$PGHOST" --port="$PGPORT" --username="$PGUSER" "$@"; }
pg_dumpall_exec(){ PGPASSWORD="$PGPASSWORD" pg_dumpall --host="$PGHOST" --port="$PGPORT" --username="$PGUSER" "$@"; }

COMP_TOOL="$(choose_comp)"
echo "[=] Compressor: $COMP_TOOL"

if [[ "$DB_TYPE" == "mysql" ]]; then
  for b in mysql mysqldump find; do have "$b" || { echo "[!] Falta: $b"; exit 2; }; done
  echo "[=] Testando conexão MySQL ${MYSQL_HOST}:${MYSQL_PORT}..."
  mysql_exec -e "SELECT VERSION();" >/dev/null; echo "[+] Conectado MySQL"
else
  for b in psql pg_dump pg_dumpall find; do have "$b" || { echo "[!] Falta: $b"; exit 2; }; done
  echo "[=] Testando conexão PostgreSQL ${PGHOST}:${PGPORT}..."
  psql_exec -c "SELECT version();" >/dev/null; echo "[+] Conectado PostgreSQL"
fi

declare -a target_dbs=()
if [[ "$DB_TYPE" == "mysql" ]]; then
  declare -a SKIP_MYSQL=("information_schema" "performance_schema" "mysql" "sys")
  should_skip_mysql(){ local db="$1"; for s in "${SKIP_MYSQL[@]}"; do [[ "$db" == "$s" ]] && return 0; done; return 1; }
  if [[ $# -ge 1 ]]; then target_dbs=("$1"); else
    while IFS= read -r db; do [[ -z "$db" ]] && continue; should_skip_mysql "$db" || target_dbs+=("$db"); done < <(mysql_exec -N -e "SHOW DATABASES;")
  fi
else
  if [[ $# -ge 1 ]]; then target_dbs=("$1"); else
    while IFS= read -r db; do [[ -z "$db" ]] && continue; [[ "$db" =~ ^template[01]$ ]] && continue; target_dbs+=("$db"); done < <(psql_exec -t -A -c "SELECT datname FROM pg_database WHERE datistemplate = false;")
  fi
fi
[[ ${#target_dbs[@]} -gt 0 ]] || { echo "[!] Nenhum banco encontrado"; exit 3; }
echo "[=] Bancos-alvo: ${target_dbs[*]}"

backup_mysql_db() {
  local db="$1"; local out="${RUN_DIR}/${db}.sql"
  local DUMP_FLAGS=( --single-transaction --quick --routines --events --triggers --hex-blob --default-character-set=utf8mb4 --skip-lock-tables )
  has_flag_mysql "column-statistics" && DUMP_FLAGS+=(--column-statistics=0)
  has_flag_mysql "set-gtid-purged"   && DUMP_FLAGS+=(--set-gtid-purged=OFF)
  has_flag_mysql "no-tablespaces"    && DUMP_FLAGS+=(--no-tablespaces)
  echo "[>] MySQL dump: ${db}"
  if [[ "$COMP_TOOL" == "zstd" ]]; then out="${out}.zst"; mysqldump_exec "${DUMP_FLAGS[@]}" --databases "$db" | zstd -T0 -19 -o "$out"
  elif [[ "$COMP_TOOL" == "pigz" ]]; then out="${out}.gz"; mysqldump_exec "${DUMP_FLAGS[@]}" --databases "$db" | pigz -9 > "$out"
  elif [[ "$COMP_TOOL" == "gzip" ]]; then out="${out}.gz"; mysqldump_exec "${DUMP_FLAGS[@]}" --databases "$db" | gzip -9 > "$out"
  else mysqldump_exec "${DUMP_FLAGS[@]}" --databases "$db" > "$out"; fi
  [[ -f "$out" ]] && echo "[+] OK ${db} -> $(fmt_bytes "$(stat -c%s "$out" 2>/dev/null || stat -f%z "$out")") -> ${out}" || { echo "[!] Falhou ${db}"; return 1; }
}
backup_postgres_db() {
  local db="$1"; local out="${RUN_DIR}/${db}.sql"
  local DUMP_FLAGS=( --format=plain --no-owner --no-privileges --encoding=UTF8 --dbname="$db" )
  echo "[>] PostgreSQL dump: ${db}"
  if [[ "$COMP_TOOL" == "zstd" ]]; then out="${out}.zst"; pg_dump_exec "${DUMP_FLAGS[@]}" | zstd -T0 -19 -o "$out"
  elif [[ "$COMP_TOOL" == "pigz" ]]; then out="${out}.gz"; pg_dump_exec "${DUMP_FLAGS[@]}" | pigz -9 > "$out"
  elif [[ "$COMP_TOOL" == "gzip" ]]; then out="${out}.gz"; pg_dump_exec "${DUMP_FLAGS[@]}" | gzip -9 > "$out"
  else pg_dump_exec "${DUMP_FLAGS[@]}" > "$out"; fi
  [[ -f "$out" ]] && echo "[+] OK ${db} -> $(fmt_bytes "$(stat -c%s "$out" 2>/dev/null || stat -f%z "$out")") -> ${out}" || { echo "[!] Falhou ${db}"; return 1; }
}

fail=0
if [[ "$DB_TYPE" == "mysql" ]]; then
  for db in "${target_dbs[@]}"; do backup_mysql_db "$db" || fail=$((fail+1)); done
else
  local globals="${RUN_DIR}/globals_roles.sql"
  echo "[=] Dump de roles/globais (pg_dumpall --globals-only)"
  if [[ "$COMP_TOOL" == "zstd" ]]; then globals="${globals}.zst"; pg_dumpall_exec --globals-only | zstd -T0 -19 -o "$globals"
  elif [[ "$COMP_TOOL" == "pigz" ]]; then globals="${globals}.gz"; pg_dumpall_exec --globals-only | pigz -9 > "$globals"
  elif [[ "$COMP_TOOL" == "gzip" ]]; then globals="${globals}.gz"; pg_dumpall_exec --globals-only | gzip -9 > "$globals"
  else pg_dumpall_exec --globals-only > "$globals"; fi
  [[ -f "$globals" ]] && echo "[+] OK globals -> $(fmt_bytes "$(stat -c%s "$globals" 2>/dev/null || stat -f%z "$globals")") -> ${globals}" || { echo "[!] Falha em globals"; fail=$((fail+1)); }
  for db in "${target_dbs[@]}"; do backup_postgres_db "$db" || fail=$((fail+1)); done
fi

if [[ "$RETENTION_DAYS" =~ ^[0-9]+$ && "$RETENTION_DAYS" -gt 0 ]]; then
  echo "[=] Limpando backups com mais de ${RETENTION_DAYS} dias em ${RUN_BASE}"
  find "${RUN_BASE}" -mindepth 1 -maxdepth 1 -type d -mtime +${RETENTION_DAYS} -print -exec rm -rf {} +
fi

ln -sfn "$RUN_DIR" "${RUN_BASE}/latest"

END_TS=$(date +%s); DUR=$((END_TS - START_TS))
printf "\n[=] Concluído: %s | Duração total: %02d:%02d:%02d | Falhas: %d\n" \
  "$(date '+%F %T')" $((DUR/3600)) $(((DUR%3600)/60)) $((DUR%60)) "$fail"

# -------- Email HTML opcional --------
send_mail_html() {
  local subject="$1"
  local html_body="$2"
  local tmp="/tmp/db_backup_mail_${DB_TYPE}_${DATE}.eml"
  {
    echo "From: ${FROM}"
    echo "To: ${EMAIL}"
    echo "Subject: ${subject}"
    echo "MIME-Version: 1.0"
    echo "Content-Type: text/html; charset=UTF-8"
    echo
    echo "${html_body}"
  } > "$tmp"
  msmtp "$EMAIL" < "$tmp"
}

if [[ "${SEND_LOG,,}" == "true" && -n "$EMAIL" && -n "$FROM" && $(command -v msmtp) ]]; then
  if [[ "${SEND_LOG_FORMAT,,}" == "html" ]]; then
    # Monta HTML simples com resumo e log em <pre>
    HTML="<html><body style='font-family:Arial,sans-serif'>
<h2>Backup ${DB_TYPE} — ${HOST}</h2>
<p><b>Data:</b> ${DATE}<br><b>Falhas:</b> ${fail}</p>
<h3>Resumo</h3>
<pre style='background:#111;color:#eee;padding:10px;border-radius:6px;white-space:pre-wrap;'>$(sed 's/&/\&amp;/g; s/</\&lt;/g' "$LOG_FILE")</pre>
</body></html>"
    if send_mail_html "DB Backup (${DB_TYPE}) - ${HOST} - ${DATE} (falhas=${fail})" "$HTML"; then
      echo "[+] Log HTML enviado para $EMAIL"
    else
      echo "[!] Falha ao enviar e-mail HTML"
    fi
  else
    {
      echo "From: $FROM"
      echo "To: $EMAIL"
      echo "Subject: DB Backup (${DB_TYPE}) - ${HOST} - ${DATE} (falhas=${fail})"
      echo ""
      cat "$LOG_FILE"
    } > /tmp/email_backup_log.txt
    if msmtp "$EMAIL" < /tmp/email_backup_log.txt; then
      echo "[+] Log texto enviado para $EMAIL"
    else
      echo "[!] Falha ao enviar e-mail texto"
    fi
  fi
fi
