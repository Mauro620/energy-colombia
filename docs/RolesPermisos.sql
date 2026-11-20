-- Iniciamos con estas validaciones
-- reconociendo los roles y permisos generados
--Consultar todos los usuarios y roles
SELECT
    rolname AS nombre_rol,
    rolsuper AS superusuario,
    rolcreatedb AS puede_crear_bd,
    rolcreaterole AS puede_crear_roles,
    rolcanlogin AS permite_login,
    rolconnlimit AS limite_conexiones
FROM pg_roles
ORDER BY rolname;

--Consultar los roles asignados a cada usuario
SELECT
    usuario.rolname AS usuario,
    grupo.rolname AS rol_asignado
FROM pg_auth_members membresia
INNER JOIN pg_roles grupo
    ON membresia.roleid = grupo.oid
INNER JOIN pg_roles usuario
    ON membresia.member = usuario.oid
ORDER BY usuario.rolname;

--Consultar los permisos de las tablas
SELECT
    grantee AS usuario_o_rol,
    table_schema,
    table_name,
    privilege_type
FROM information_schema.role_table_grants
WHERE table_schema = 'energia'
ORDER BY grantee, table_name, privilege_type;

-- Verificar los permisos en la práctica
-- Verificar usuario actual
SELECT CURRENT_USER;

-- Verificar usuario de sesión
SELECT SESSION_USER;

--Prueba 1 Simular el analista

SET ROLE rol_analista;

-- Permitido
SELECT *
FROM energia.mediciones
LIMIT 10;

-- No permitido
DELETE FROM energia.mediciones
WHERE id_medicion = 1;

-- Volver al usuario original
RESET ROLE;

-- Simular el operador
SET ROLE rol_operador;

-- Permitido
INSERT INTO energia.mediciones (
    id_ubicacion,
    fecha_medicion,
    energia_generada,
    temperatura,
    estado
)
VALUES (
    2,
    CURRENT_TIMESTAMP,
    90.50,
    25.50,
    'REGISTRADA'
);

-- No permitido
DELETE FROM energia.mediciones
WHERE id_medicion = 2;

RESET ROLE;

--SEGURIDAD
--Evitar que cualquier usuario cree objetos
REVOKE CREATE ON SCHEMA public FROM PUBLIC;

-- Evitar conexiones no autorizados
REVOKE CONNECT ON DATABASE energia_db FROM PUBLIC;

GRANT CONNECT ON DATABASE energia_db TO rol_administrador;
GRANT CONNECT ON DATABASE energia_db TO rol_analista;
GRANT CONNECT ON DATABASE energia_db TO rol_operador;

-- consultar quien tiene acceso a BD
SELECT
    datname,
    datacl
FROM pg_database
WHERE datname = 'energia_db';

-- Consultar permisos especificos
SELECT
    has_table_privilege(
        'usuario_analista',
        'energia.mediciones',
        'SELECT'
    ) AS puede_consultar,

    has_table_privilege(
        'usuario_analista',
        'energia.mediciones',
        'DELETE'
    ) AS puede_eliminar;

    
