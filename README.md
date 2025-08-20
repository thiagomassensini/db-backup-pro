# db-backup-pro

Backup otimizado para **MySQL/MariaDB** e **PostgreSQL**, com compressão inteligente, retenção, logs, e envio de relatório por e-mail (texto ou HTML via `msmtp`).

Autor: **Thiago Motta Massensini**  

Contato: **suporte@hextec.com.br**  

Licença: **MIT**

---

## ✨ Recursos

- **MySQL/MariaDB** via `mysqldump` (consistente com `--single-transaction --quick`, inclui rotinas, eventos e gatilhos).
- **PostgreSQL** via `pg_dump` por banco e `pg_dumpall --globals-only` para roles/globais.
- **Compressão automática**: tenta `zstd` > `pigz` > `gzip` (ou escolha manual com `COMP`).
- **Retenção por dias** com limpeza automática dos diretórios antigos.
- **Logs detalhados** e symlink `latest` para a última execução.
- **Envio de log por e-mail** (texto ou **HTML**) via `msmtp`.
- Configuração por **variáveis de ambiente** ou arquivo `.env` (ex.: `/etc/db_backup.env`).

---

## 🗂️ Estrutura de saída

```
/backup/db/<hostname>/<db_type>/<YYYY-MM-DD-HHMMSS>/
  ├─ globals_roles.sql(.zst|.gz)?     # (apenas PostgreSQL)
  ├─ <database>.sql(.zst|.gz)
  └─ ...

/backup/db/<hostname>/<db_type>/latest -> symlink para a execução mais recente
/var/log/db-backup/backup_<db_type>_<host>_<timestamp>.log
```

---

## 📦 Requisitos

- Comuns: `bash`, `find`, `numfmt` (coreutils), compressor (`zstd`/`pigz`/`gzip`).
- MySQL/MariaDB: `mysql`, `mysqldump`.
- PostgreSQL: `psql`, `pg_dump`, `pg_dumpall`.
- (Opcional) `msmtp` para envio de log por e-mail.

---

## 🚀 Instalação

```bash
# copie o script para um local do PATH
sudo install -m 0755 db_backup_pro.sh /usr/local/bin/db_backup_pro.sh

# crie diretórios padrão
sudo mkdir -p /backup/db /var/log/db-backup
sudo chown -R root:root /backup/db /var/log/db-backup
```

---

## ⚙️ Configuração via `.env` (opcional)

Crie `/etc/db_backup.env` (ou defina `ENV_FILE` apontando para outro local):

```bash
# Tipo de banco: mysql | postgres
DB_TYPE=mysql

# Diretórios
BACKUP_DIR=/backup/db
LOG_DIR=/var/log/db-backup
RETENTION_DAYS=10

# Compressão: auto | zstd | pigz | gzip
COMP=auto

# MySQL/MariaDB
MYSQL_HOST=127.0.0.1
MYSQL_PORT=3306
MYSQL_USER=root
MYSQL_PASSWORD=senha_aqui

# PostgreSQL
PGHOST=127.0.0.1
PGPORT=5432
PGUSER=postgres
PGPASSWORD=senha_aqui
PGDATABASE=postgres

# Envio de log (opcional)
SEND_LOG=true
SEND_LOG_FORMAT=html        # text | html
EMAIL=suporte@hextec.com.br
FROM=backup@$(hostname -f 2>/dev/null || hostname).local
```

> **Dica:** Não faça commit de arquivos `.env` contendo credenciais.

---

## 🧪 Uso

### MySQL/MariaDB
```bash
# todos os bancos (exceto system)
DB_TYPE=mysql /usr/local/bin/db_backup_pro.sh

# um banco específico
DB_TYPE=mysql /usr/local/bin/db_backup_pro.sh nome_do_banco
```

### PostgreSQL
```bash
# todos os bancos (exceto templates)
DB_TYPE=postgres /usr/local/bin/db_backup_pro.sh

# um banco específico
DB_TYPE=postgres /usr/local/bin/db_backup_pro.sh nome_do_db
```

---

## ✉️ Envio de log por e-mail (texto/HTML) com `msmtp`

O script envia o log completo ao final da execução quando `SEND_LOG=true`. Defina `SEND_LOG_FORMAT=html` para receber um e-mail com `Content-Type: text/html` contendo o log em `<pre>`.

### Instalação do `msmtp` (Ubuntu/Debian)
```bash
sudo apt update
sudo apt install -y msmtp msmtp-mta
```

### Configuração do SMTP (`/etc/msmtprc`)

Crie o arquivo `/etc/msmtprc` e aplique permissões seguras:

```bash
sudo nano /etc/msmtprc
sudo chown root:root /etc/msmtprc
sudo chmod 600 /etc/msmtprc
```

**Exemplo 1 — SMTP genérico (provedor próprio):**
```ini
# /etc/msmtprc
defaults
auth           on
tls            on
tls_trust_file /etc/ssl/certs/ca-certificates.crt
logfile        /var/log/msmtp.log

account        default
host           mail.seudominio.com
port           587
from           suporte@hextec.com.br
user           suporte@hextec.com.br
password       SUA_SENHA_AQUI
```

**Exemplo 2 — Gmail (App Password):**
```ini
defaults
auth           on
tls            on
tls_starttls   on
tls_trust_file /etc/ssl/certs/ca-certificates.crt
logfile        /var/log/msmtp.log

account        default
host           smtp.gmail.com
port           587
from           suporte@hextec.com.br
user           suporte@hextec.com.br
password       APP_PASSWORD_DO_GMAIL
```

**Exemplo 3 — Office 365/Outlook:**
```ini
defaults
auth           on
tls            on
tls_starttls   on
tls_trust_file /etc/ssl/certs/ca-certificates.crt
logfile        /var/log/msmtp.log

account        default
host           smtp.office365.com
port           587
from           suporte@hextec.com.br
user           suporte@hextec.com.br
password       SUA_SENHA_AQUI
```

> **Obs.:** Para provedores que exigem OAuth2, prefira **App Password** para uso em servidores/headless.

### Teste rápido do e-mail
```bash
echo "teste ok" | msmtp -a default suporte@hextec.com.br
```

Se chegar, o `msmtp` está pronto. Em seguida, defina no `.env`:
```bash
SEND_LOG=true
SEND_LOG_FORMAT=html   # ou text
EMAIL=suporte@hextec.com.br
FROM=backup@$(hostname -f 2>/dev/null || hostname).local
```

---

## ⏲️ Crontab (exemplos)

```bash
# MySQL todos os dias às 02:15
15 2 * * * DB_TYPE=mysql /usr/local/bin/db_backup_pro.sh >> /var/log/cron-db-backup.log 2>&1

# PostgreSQL todos os dias às 02:45
45 2 * * * DB_TYPE=postgres /usr/local/bin/db_backup_pro.sh >> /var/log/cron-db-backup.log 2>&1
```

---

## ♻️ Restauração (resumo)

### MySQL/MariaDB
```bash
# arquivo .sql (ou .sql.gz/.zst com zcat / zstdcat)
mysql -h HOST -P PORT -u USER -p <database> < dump.sql
```

### PostgreSQL
```bash
# roles/globais (se aplicável)
psql -h HOST -p PORT -U USER -d postgres -f globals_roles.sql

# base de dados (crie antes, se necessário)
createdb -h HOST -p PORT -U USER meu_db || true
psql -h HOST -p PORT -U USER -d meu_db -f meu_db.sql
```

---

## 🧰 Troubleshooting rápido

- **Erro de autenticação no e-mail:** verifique `/etc/msmtprc` e permissões (600), teste com `echo "ok" | msmtp ...`.
- **Aviso `--column-statistics` no MySQL:** o script desliga automaticamente com `--column-statistics=0` quando necessário.
- **GTID/replicação:** o script define `--set-gtid-purged=OFF` para evitar conflitos em versões antigas.
- **`numfmt: command not found`**: instale `coreutils`.

---

## 🗒️ Changelog

### v1.1
- Suporte a envio de e-mail **HTML** via `msmtp` (`SEND_LOG_FORMAT=html`).
- Documentação de **SMTP** detalhada no README.
- Pequenas melhorias de log e robustez.

### v1.0
- Primeira versão pública (MySQL/MariaDB + PostgreSQL, compressão automática, retenção, logs, symlink `latest`).

---

## 📜 Licença

Este projeto é distribuído sob a licença **MIT**. Consulte o arquivo `LICENSE`.
