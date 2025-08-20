# db-backup-pro

Backup otimizado para **MySQL/MariaDB** e **PostgreSQL**, com compressão inteligente, retenção, logs e estrutura organizada por host/data/tipo.

Autor: **Thiago Motta Massensini**  
Contato: **suporte@hextec.com.br**  
Licença: **MIT**

## Recursos
- MySQL/MariaDB via `mysqldump` (consistente com `--single-transaction --quick`, inclui rotinas/eventos/gatilhos).
- PostgreSQL via `pg_dump` por banco e `pg_dumpall --globals-only` para roles/globais.
- Compressão automática: tenta `zstd` > `pigz` > `gzip` (ou escolha manual).
- Retenção por dias com limpeza automática.
- Log detalhado e symlink `latest` para última execução.
- `.env` opcional para configurar credenciais/variáveis.

## Estrutura de saída
```
/backup/db/<hostname>/<db_type>/<YYYY-MM-DD-HHMMSS>/
  ├─ globals_roles.sql(.zst|.gz)?     # (apenas PostgreSQL)
  ├─ <database>.sql(.zst|.gz)
  └─ ...

/backup/db/<hostname>/<db_type>/latest -> symlink para a execução mais recente
/var/log/db-backup/backup_<db_type>_<host>_<timestamp>.log
```

## Requisitos
- Comuns: `bash`, `find`, `numfmt` (coreutils), compressor (`zstd`/`pigz`/`gzip`).
- MySQL/MariaDB: `mysql`, `mysqldump`.
- PostgreSQL: `psql`, `pg_dump`, `pg_dumpall`.
- (Opcional) `msmtp` para envio de log por email.

## Instalação
```bash
sudo install -m 0755 db_backup_pro.sh /usr/local/bin/db_backup_pro.sh
sudo mkdir -p /backup/db /var/log/db-backup
sudo chown -R root:root /backup/db /var/log/db-backup
```

## Configuração via `.env` (opcional)
Crie `/etc/db_backup.env` (ou defina `ENV_FILE`):
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
EMAIL=suporte@hextec.com.br
FROM=backup@$(hostname -f 2>/dev/null || hostname).local
```

## Uso
### MySQL/MariaDB
```bash
DB_TYPE=mysql /usr/local/bin/db_backup_pro.sh              # todos os bancos (exceto system)
DB_TYPE=mysql /usr/local/bin/db_backup_pro.sh meu_banco    # um banco específico
```

### PostgreSQL
```bash
DB_TYPE=postgres /usr/local/bin/db_backup_pro.sh           # todos os bancos (exceto templates)
DB_TYPE=postgres /usr/local/bin/db_backup_pro.sh meu_db    # um banco específico
```

> Dica: você pode exportar `DB_TYPE` e demais variáveis no ambiente ou usar o `.env`.

## Crontab (exemplos)
```bash
# MySQL todos os dias às 02:15
15 2 * * * DB_TYPE=mysql /usr/local/bin/db_backup_pro.sh >> /var/log/cron-db-backup.log 2>&1

# PostgreSQL todos os dias às 02:45
45 2 * * * DB_TYPE=postgres /usr/local/bin/db_backup_pro.sh >> /var/log/cron-db-backup.log 2>&1
```

## Restauração (resumo)
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

## Observações
- Este projeto e os scripts são de **autoria de Thiago Motta Massensini**.
- Sem referências a empresas anteriores; use o email **suporte@hextec.com.br** para contato.
- Teste em ambiente de staging antes de usar em produção.
