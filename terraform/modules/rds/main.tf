# RDS module — provisions MySQL 8.0 instance for the three database-backed services.
# Single shared 'petclinic' database (customers, visits, vets share one instance per ADR-0003).
# Credentials generated via random_password and stored in Secrets Manager.
# Implemented in: PETPLAT-22 (RDS instance), PETPLAT-23 (credentials + Secrets Manager).
