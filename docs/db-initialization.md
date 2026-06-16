# Database Initialization Strategy

**Last Updated:** 2026-06-15
**PETPLAT-24**

## Purpose

Describes how the three MySQL-backed Spring Petclinic services (customers, visits, vets) initialize their schemas on first startup and how schema changes are managed ongoing.

## Table of Contents

1. [Strategy](#strategy)
2. [Service–Database Mapping](#servicedatabase-mapping)
3. [Startup Order](#startup-order)
4. [Spring Boot Configuration](#spring-boot-configuration)
5. [Running Migrations Manually](#running-migrations-manually)
6. [Resetting a Schema](#resetting-a-schema)

---

## Strategy

Spring Petclinic services use **Spring Boot's built-in SQL initialization** (`spring.sql.init.mode=always`). Each service ships with a `schema.sql` and `data.sql` in its classpath. On startup with the `mysql` profile active, the service:

1. Connects to the shared `petclinic` database using JDBC credentials from Secrets Manager.
2. Executes `schema.sql` to create tables (`CREATE TABLE IF NOT EXISTS`).
3. Executes `data.sql` to seed reference data (vets, specialties).

This approach requires no separate migration tooling for the learning environment. There is no Flyway or Liquibase involved.

> **Production consideration:** For real production workloads, replace `spring.sql.init.mode=always` with a proper migration tool (Flyway/Liquibase) and set `spring.sql.init.mode=never`.

---

## Service–Database Mapping

All three services share a **single RDS instance** and a single database named `petclinic`. Tables are namespaced by service domain.

| Service | Tables Created |
|---------|----------------|
| `customers-service` | `owners`, `pets`, `types` |
| `visits-service` | `visits` |
| `vets-service` | `vets`, `specialties`, `vet_specialties` |

The shared database identifier is `petclinic-{env}-mysql` and the database name is `petclinic`.

---

## Startup Order

Services must start in this order due to dependencies:

```
1. config-server    (Git-backed config, no DB)
2. discovery-server (Eureka, no DB)
3. customers-service, visits-service, vets-service  (DB init on startup)
4. api-gateway, admin-server, genai-service         (no DB)
```

Kubernetes init containers enforce this order — see `helm-values/customers-service.yaml`, `helm-values/visits-service.yaml`, and `helm-values/vets-service.yaml`.

---

## Spring Boot Configuration

The `mysql` Spring profile activates database connectivity. Add `mysql` to `SPRING_PROFILES_ACTIVE` alongside `docker`:

```yaml
# In helm-values/{service}.yaml
env:
  - name: SPRING_PROFILES_ACTIVE
    value: "docker,mysql"
  - name: SPRING_DATASOURCE_URL
    value: "jdbc:mysql://{rds-endpoint}:3306/petclinic"
  - name: SPRING_SQL_INIT_MODE
    value: "always"
```

Credentials are injected via External Secrets Operator from `petclinic/{env}/rds-credentials` in AWS Secrets Manager. The secret JSON format is:

```json
{"username": "petclinic", "password": "<generated>"}
```

Connection pool configuration (via HikariCP defaults in Spring Boot) is sufficient for db.t4g.micro with 1–2 replicas per service.

---

## Running Migrations Manually

To re-run schema initialization against dev RDS directly (e.g., after a schema reset):

```bash
# Get RDS endpoint from Terraform output
RDS_ENDPOINT=$(cd terraform/environments/dev && terraform output -raw rds_endpoint)

# Get credentials from Secrets Manager
SECRET=$(aws secretsmanager get-secret-value \
  --secret-id petclinic/dev/rds-credentials \
  --region eu-central-1 \
  --query SecretString \
  --output text)

DB_USER=$(echo $SECRET | jq -r .username)
DB_PASS=$(echo $SECRET | jq -r .password)

# Connect to verify schema
mysql -h "${RDS_ENDPOINT}" -u "${DB_USER}" -p"${DB_PASS}" petclinic -e "SHOW TABLES;"
```

---

## Resetting a Schema

To wipe and re-initialize all tables in dev (non-destructive in prod — never run against prod without approval):

```bash
mysql -h "${RDS_ENDPOINT}" -u "${DB_USER}" -p"${DB_PASS}" petclinic \
  -e "DROP TABLE IF EXISTS visits, pets, owners, types, vet_specialties, specialties, vets;"
```

Then restart the three services — Spring Boot re-creates all tables on next startup.
