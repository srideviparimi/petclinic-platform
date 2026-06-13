# Secrets module — provisions non-RDS application secrets in AWS Secrets Manager.
# Handles: petclinic/{env}/openai-api-key (and optional config-server git credentials).
# RDS credentials are managed by the rds module (PETPLAT-23) — NOT here.
# Implemented in: PETPLAT-33.
