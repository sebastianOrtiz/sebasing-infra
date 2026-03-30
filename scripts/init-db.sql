-- =============================================================================
-- init-db.sql — Inicializacion de schemas para todos los servicios
-- Se ejecuta automaticamente al crear el contenedor de PostgreSQL.
-- =============================================================================

-- Schema para NexusCRM API (FastAPI)
CREATE SCHEMA IF NOT EXISTS crm;

-- Schema para Event-Driven Service (Go)
CREATE SCHEMA IF NOT EXISTS events;

-- Schema para Semantic Search API (FastAPI)
CREATE SCHEMA IF NOT EXISTS search;

-- Otorgar permisos al usuario por defecto en cada schema
DO $$
DECLARE
    current_user_name TEXT := current_user;
BEGIN
    EXECUTE format('GRANT ALL ON SCHEMA crm TO %I', current_user_name);
    EXECUTE format('GRANT ALL ON SCHEMA events TO %I', current_user_name);
    EXECUTE format('GRANT ALL ON SCHEMA search TO %I', current_user_name);
END
$$;
