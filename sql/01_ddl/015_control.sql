-- Bitacora de cargas (DQ07) y cuarentena (DQ05). Los registros rechazados pertenecen a su lote: ON DELETE CASCADE.

CREATE TABLE IF NOT EXISTS control.carga_lote (
  lote_id            bigint        GENERATED ALWAYS AS IDENTITY,
  fuente             varchar(60)   NOT NULL,
  tabla_destino      varchar(80)   NOT NULL,
  estado             control.estado_lote NOT NULL DEFAULT 'en_curso',
  iniciado_en        timestamptz   NOT NULL DEFAULT now(),
  finalizado_en      timestamptz,
  filas_leidas       bigint        NOT NULL DEFAULT 0,
  filas_insertadas   bigint        NOT NULL DEFAULT 0,
  filas_actualizadas bigint        NOT NULL DEFAULT 0,
  filas_omitidas     bigint        NOT NULL DEFAULT 0,
  filas_rechazadas   bigint        NOT NULL DEFAULT 0,
  mensaje            text,
  CONSTRAINT pk_carga_lote PRIMARY KEY (lote_id)
);

CREATE TABLE IF NOT EXISTS control.registro_rechazado (
  rechazo_id   bigint       GENERATED ALWAYS AS IDENTITY,
  lote_id      bigint       NOT NULL,
  regla        varchar(20)  NOT NULL,
  motivo       text         NOT NULL,
  registro     jsonb        NOT NULL,
  rechazado_en timestamptz  NOT NULL DEFAULT now(),
  CONSTRAINT pk_registro_rechazado PRIMARY KEY (rechazo_id),
  CONSTRAINT fk_registro_rechazado_lote FOREIGN KEY (lote_id)
    REFERENCES control.carga_lote (lote_id) ON UPDATE CASCADE ON DELETE CASCADE
);
CREATE INDEX IF NOT EXISTS ix_registro_rechazado_lote_regla ON control.registro_rechazado (lote_id, regla);
