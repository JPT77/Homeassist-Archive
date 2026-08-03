-- Role: homeassist
-- DROP ROLE IF EXISTS homeassist;
CREATE ROLE homeassist WITH
  LOGIN
  NOSUPERUSER
  INHERIT
  NOCREATEDB
  NOCREATEROLE
  NOREPLICATION
  NOBYPASSRLS
  ENCRYPTED PASSWORD 'SCRAM-SHA-256$4096:TODO';

-- Database: homeassist
-- DROP DATABASE IF EXISTS homeassist;
CREATE DATABASE homeassist
    WITH
    OWNER = homeassist
    ENCODING = 'UTF8'
    LC_COLLATE = 'de_DE.UTF-8'
    LC_CTYPE = 'de_DE.UTF-8'
    LOCALE_PROVIDER = 'libc'
    TABLESPACE = pg_default
    CONNECTION LIMIT = -1
    IS_TEMPLATE = False;

-- Table: public.statistics_meta
-- DROP TABLE IF EXISTS public.statistics_meta;
CREATE TABLE IF NOT EXISTS public.statistics_meta
(
    id integer NOT NULL,
    statistic_id text COLLATE pg_catalog."default" NOT NULL,
    source text COLLATE pg_catalog."default",
    unit_of_measurement text COLLATE pg_catalog."default",
    has_mean boolean,
    has_sum boolean,
    name text COLLATE pg_catalog."default",
    CONSTRAINT statistics_meta_pkey PRIMARY KEY (id),
    CONSTRAINT statistics_meta_statistic_id_key UNIQUE (statistic_id)
)

TABLESPACE pg_default;

ALTER TABLE IF EXISTS public.statistics_meta
    OWNER to postgres;

REVOKE ALL ON TABLE public.statistics_meta FROM homeassist;
GRANT INSERT, SELECT, UPDATE ON TABLE public.statistics_meta TO homeassist;
GRANT ALL ON TABLE public.statistics_meta TO postgres;

COMMENT ON TABLE public.statistics_meta
    IS 'Metadata for Home Assistant statistics.';

-- Table: public.statistics_short_term
-- DROP TABLE IF EXISTS public.statistics_short_term;
CREATE TABLE IF NOT EXISTS public.statistics_short_term
(
    metadata_id integer NOT NULL,
    start_at timestamp with time zone NOT NULL,
    created_at timestamp with time zone,
    mean double precision,
    mean_weight double precision,
    min double precision,
    max double precision,
    state double precision,
    sum double precision,
    last_reset_at timestamp with time zone,
    CONSTRAINT statistics_short_term_pkey PRIMARY KEY (metadata_id, start_at),
    CONSTRAINT statistics_short_term_metadata_id_fkey FOREIGN KEY (metadata_id)
        REFERENCES public.statistics_meta (id) MATCH SIMPLE
        ON UPDATE NO ACTION
        ON DELETE NO ACTION
)

TABLESPACE pg_default;

ALTER TABLE IF EXISTS public.statistics_short_term
    OWNER to postgres;

REVOKE ALL ON TABLE public.statistics_short_term FROM homeassist;
GRANT INSERT, SELECT, UPDATE ON TABLE public.statistics_short_term TO homeassist;
GRANT ALL ON TABLE public.statistics_short_term TO postgres;

COMMENT ON TABLE public.statistics_short_term
    IS '5-minute aggregated Home Assistant statistics.';

-- Index: idx_statistics_metadata
-- DROP INDEX IF EXISTS public.idx_statistics_metadata;
CREATE INDEX IF NOT EXISTS idx_statistics_metadata
    ON public.statistics_short_term USING btree
    (metadata_id ASC NULLS LAST)
    TABLESPACE pg_default;

-- Index: idx_statistics_metadata_start
-- DROP INDEX IF EXISTS public.idx_statistics_metadata_start;
CREATE INDEX IF NOT EXISTS idx_statistics_metadata_start
    ON public.statistics_short_term USING btree
    (metadata_id ASC NULLS LAST, start_at ASC NULLS LAST)
    TABLESPACE pg_default;

-- Index: idx_statistics_start_at
-- DROP INDEX IF EXISTS public.idx_statistics_start_at;
CREATE INDEX IF NOT EXISTS idx_statistics_start_at
    ON public.statistics_short_term USING btree
    (start_at ASC NULLS LAST)
    TABLESPACE pg_default;

ALTER TABLE IF EXISTS public.statistics_short_term
    OWNER to postgres;

COMMENT ON TABLE public.statistics_short_term
    IS '5-minute aggregated Home Assistant statistics.';

-- Index: idx_statistics_metadata
-- DROP INDEX IF EXISTS public.idx_statistics_metadata;
CREATE INDEX IF NOT EXISTS idx_statistics_metadata
    ON public.statistics_short_term USING btree
    (metadata_id ASC NULLS LAST)
    TABLESPACE pg_default;

-- Index: idx_statistics_metadata_start
-- DROP INDEX IF EXISTS public.idx_statistics_metadata_start;
CREATE INDEX IF NOT EXISTS idx_statistics_metadata_start
    ON public.statistics_short_term USING btree
    (metadata_id ASC NULLS LAST, start_at ASC NULLS LAST)
    TABLESPACE pg_default;

-- Index: idx_statistics_start_at
-- DROP INDEX IF EXISTS public.idx_statistics_start_at;
CREATE INDEX IF NOT EXISTS idx_statistics_start_at
    ON public.statistics_short_term USING btree
    (start_at ASC NULLS LAST)
    TABLESPACE pg_default;

-- Table: public.import_history
-- DROP TABLE IF EXISTS public.import_history;
CREATE TABLE IF NOT EXISTS public.import_history
(
    filename text COLLATE pg_catalog."default" NOT NULL,
    imported_at timestamp with time zone NOT NULL DEFAULT now(),
    rows_imported integer NOT NULL,
    CONSTRAINT import_history_pkey PRIMARY KEY (filename)
)

TABLESPACE pg_default;

ALTER TABLE IF EXISTS public.import_history
    OWNER to postgres;

REVOKE ALL ON TABLE public.import_history FROM homeassist;
GRANT INSERT, SELECT, UPDATE ON TABLE public.import_history TO homeassist;
GRANT ALL ON TABLE public.import_history TO postgres;