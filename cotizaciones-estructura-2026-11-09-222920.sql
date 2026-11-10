--
-- PostgreSQL database dump
--

\restrict 0NrES0Mc3kfSYQWuOnxd6znHguogT7xzD2imfSrA9uYJSkN2NGljcc8luD6wn1q

-- Dumped from database version 16.15
-- Dumped by pg_dump version 16.15

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: asegurar_cliente_cotizacion(bigint, text, text, text, text, text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.asegurar_cliente_cotizacion(cuenta bigint, nombre text, tipo text, documento text, correo text, telefono text, contacto text) RETURNS bigint
    LANGUAGE plpgsql
    AS $$
DECLARE cliente_id bigint;
BEGIN
    IF cuenta IS NULL OR cuenta < 1 OR btrim(nombre) = '' THEN
        RAISE EXCEPTION 'Cuenta o nombre de cliente inválido';
    END IF;
    -- Serialize matching and insertion within the same account.
    PERFORM pg_advisory_xact_lock(cuenta);
    SELECT id INTO cliente_id FROM clientes
    WHERE owner_id = cuenta
      AND lower(btrim(nombre_comercial)) = lower(btrim(nombre))
      AND upper(btrim(rfc)) = upper(btrim(coalesce(documento, '')))
    ORDER BY id LIMIT 1;
    IF cliente_id IS NULL THEN
        INSERT INTO clientes(owner_id, nombre_comercial, tipo_cliente, rfc,
                             correo_contacto, telefono_contacto, atencion_a)
        VALUES (cuenta, btrim(nombre), coalesce(nullif(tipo, ''), 'Empresa'),
                upper(btrim(coalesce(documento, ''))), coalesce(correo, ''),
                coalesce(telefono, ''), coalesce(contacto, ''))
        RETURNING id INTO cliente_id;
    END IF;
    RETURN cliente_id;
END $$;


--
-- Name: registrar_cambio_nombre_usuario(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.registrar_cambio_nombre_usuario() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
    ultimo_cambio TIMESTAMPTZ;
    instante TIMESTAMPTZ;
BEGIN
    SELECT cambiado_en INTO ultimo_cambio
    FROM historial_nombre_usuario
    WHERE user_id = OLD.id
    ORDER BY cambiado_en DESC
    LIMIT 1;

    instante := clock_timestamp();
    IF ultimo_cambio + interval '1440 hours' > instante THEN
        RAISE EXCEPTION USING ERRCODE = 'P0060', MESSAGE = 'Solo puedes cambiar tu nombre cada 60 días';
    END IF;

    INSERT INTO historial_nombre_usuario (user_id, nombre_anterior, nombre_nuevo, cambiado_en)
    VALUES (OLD.id, OLD.nombre, NEW.nombre, instante);
    RETURN NEW;
END;
$$;


--
-- Name: registrar_cambio_perfil_comercial(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.registrar_cambio_perfil_comercial() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
    ultimo_cambio TIMESTAMPTZ;
    instante TIMESTAMPTZ;
BEGIN
    IF OLD.tipo IS DISTINCT FROM NEW.tipo THEN
        RAISE EXCEPTION USING ERRCODE = 'P0061', MESSAGE = 'El tipo de cuenta no se puede cambiar';
    END IF;

    SELECT cambiado_en INTO ultimo_cambio
    FROM historial_perfil_comercial
    WHERE user_id = OLD.user_id
    ORDER BY cambiado_en DESC
    LIMIT 1;

    instante := clock_timestamp();
    IF ultimo_cambio + interval '1440 hours' > instante THEN
        RAISE EXCEPTION USING ERRCODE = 'P0060', MESSAGE = 'Solo puedes editar tus datos comerciales cada 60 días';
    END IF;

    INSERT INTO historial_perfil_comercial (user_id, datos_anteriores, datos_nuevos, cambiado_en)
    VALUES (OLD.user_id,
        jsonb_build_object('comercial', OLD.comercial, 'razonSocial', OLD.razon_social, 'rfc', OLD.rfc, 'telefono', OLD.telefono, 'direccion', OLD.direccion),
        jsonb_build_object('comercial', NEW.comercial, 'razonSocial', NEW.razon_social, 'rfc', NEW.rfc, 'telefono', NEW.telefono, 'direccion', NEW.direccion),
        instante);
    RETURN NEW;
END;
$$;


SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: auth_sessions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.auth_sessions (
    token_hash character(64) NOT NULL,
    user_id bigint NOT NULL,
    expires_at timestamp with time zone NOT NULL
);


--
-- Name: clientes; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.clientes (
    id bigint NOT NULL,
    nombre_comercial character varying(150) NOT NULL,
    tipo_cliente character varying(50) DEFAULT 'Empresa'::character varying NOT NULL,
    rfc character varying(13) DEFAULT ''::character varying NOT NULL,
    correo_contacto character varying(120) DEFAULT ''::character varying NOT NULL,
    telefono_contacto character varying(20) DEFAULT ''::character varying NOT NULL,
    atencion_a character varying(150) DEFAULT ''::character varying NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    owner_id bigint NOT NULL
);


--
-- Name: clientes_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.clientes_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: clientes_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.clientes_id_seq OWNED BY public.clientes.id;


--
-- Name: cotizaciones; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.cotizaciones (
    id bigint NOT NULL,
    folio character varying(12) NOT NULL,
    version integer DEFAULT 1 NOT NULL,
    estado character varying(20) DEFAULT 'Aceptada'::character varying NOT NULL,
    fecha_creacion timestamp with time zone DEFAULT now() NOT NULL,
    id_cliente bigint,
    tipo_cliente character varying(50) DEFAULT 'Empresa'::character varying NOT NULL,
    razon_social character varying(150) DEFAULT ''::character varying NOT NULL,
    rfc character varying(13) DEFAULT ''::character varying NOT NULL,
    nombre_cliente character varying(150) DEFAULT ''::character varying NOT NULL,
    nombre_comercial character varying(150) DEFAULT ''::character varying NOT NULL,
    atencion_a character varying(150) DEFAULT ''::character varying NOT NULL,
    nombre_asesor character varying(150) DEFAULT ''::character varying NOT NULL,
    moneda character varying(10) DEFAULT 'MXN'::character varying NOT NULL,
    vigencia_hasta date,
    correo_contacto character varying(120) DEFAULT ''::character varying NOT NULL,
    telefono_contacto character varying(20) DEFAULT ''::character varying NOT NULL,
    precios_incluyen_iva boolean DEFAULT true NOT NULL,
    porcentaje_iva double precision DEFAULT 16 NOT NULL,
    porcentaje_anticipo double precision,
    tiempo_entrega character varying(150) DEFAULT ''::character varying NOT NULL,
    condiciones_pago text DEFAULT ''::text NOT NULL,
    notas_comerciales text DEFAULT ''::text NOT NULL,
    metodos_pago text DEFAULT ''::text NOT NULL,
    costo double precision DEFAULT 0 NOT NULL,
    subtotal double precision DEFAULT 0 NOT NULL,
    impuestos double precision DEFAULT 0 NOT NULL,
    total double precision DEFAULT 0 NOT NULL,
    utilidad_estimada double precision DEFAULT 0 NOT NULL,
    owner_id bigint NOT NULL,
    CONSTRAINT cotizaciones_metodos_pago_longitud CHECK ((char_length(metodos_pago) <= 100)),
    CONSTRAINT cotizaciones_porcentajes_validos CHECK ((((porcentaje_iva >= (0)::double precision) AND (porcentaje_iva <= (100)::double precision)) AND (porcentaje_iva = (round((porcentaje_iva)::numeric, 2))::double precision) AND ((porcentaje_anticipo IS NULL) OR (((porcentaje_anticipo >= (0)::double precision) AND (porcentaje_anticipo <= (100)::double precision)) AND (porcentaje_anticipo = (round((porcentaje_anticipo)::numeric, 2))::double precision))))),
    CONSTRAINT cotizaciones_textos_longitud CHECK (((char_length((tiempo_entrega)::text) <= 100) AND (char_length(condiciones_pago) <= 100) AND (char_length(notas_comerciales) <= 100)))
);


--
-- Name: cotizaciones_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.cotizaciones_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: cotizaciones_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.cotizaciones_id_seq OWNED BY public.cotizaciones.id;


--
-- Name: documentos_cotizacion; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.documentos_cotizacion (
    cotizacion_id bigint NOT NULL,
    version integer NOT NULL,
    instantanea jsonb,
    pdf bytea,
    generado_en timestamp with time zone,
    CONSTRAINT documentos_cotizacion_check CHECK (((instantanea IS NULL) <> (pdf IS NULL))),
    CONSTRAINT documentos_cotizacion_check1 CHECK (((pdf IS NULL) = (generado_en IS NULL)))
);


--
-- Name: eliminacion_cuenta; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.eliminacion_cuenta (
    user_id bigint NOT NULL,
    sesion_hash character(64) NOT NULL,
    codigo_hash bytea NOT NULL,
    permiso_hash bytea,
    intentos smallint DEFAULT 0 NOT NULL,
    expira_en timestamp with time zone NOT NULL,
    reenviar_desde timestamp with time zone NOT NULL,
    CONSTRAINT eliminacion_cuenta_intentos_check CHECK (((intentos >= 0) AND (intentos <= 5)))
);


--
-- Name: historial_nombre_usuario; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.historial_nombre_usuario (
    id bigint NOT NULL,
    user_id bigint NOT NULL,
    nombre_anterior character varying(60) NOT NULL,
    nombre_nuevo character varying(60) NOT NULL,
    cambiado_en timestamp with time zone NOT NULL,
    CONSTRAINT historial_nombre_usuario_check CHECK (((nombre_anterior)::text <> (nombre_nuevo)::text))
);


--
-- Name: historial_nombre_usuario_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.historial_nombre_usuario ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.historial_nombre_usuario_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: historial_perfil_comercial; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.historial_perfil_comercial (
    id bigint NOT NULL,
    user_id bigint NOT NULL,
    datos_anteriores jsonb NOT NULL,
    datos_nuevos jsonb NOT NULL,
    cambiado_en timestamp with time zone NOT NULL
);


--
-- Name: historial_perfil_comercial_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.historial_perfil_comercial ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.historial_perfil_comercial_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: partidas; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.partidas (
    id bigint NOT NULL,
    cotizacion_id bigint NOT NULL,
    numero_partida integer NOT NULL,
    descripcion character varying(200) DEFAULT ''::character varying NOT NULL,
    especificaciones_tecnicas text DEFAULT ''::text NOT NULL,
    sku character varying(50) DEFAULT ''::character varying NOT NULL,
    cantidad double precision DEFAULT 0 NOT NULL,
    unidad character varying(20) DEFAULT 'PZA'::character varying NOT NULL,
    precio_unitario_compra double precision DEFAULT 0 NOT NULL,
    precio_unitario_venta double precision DEFAULT 0 NOT NULL,
    porcentaje_descuento double precision DEFAULT 0 NOT NULL,
    importe double precision DEFAULT 0 NOT NULL,
    requiere_compra boolean DEFAULT false NOT NULL,
    estado_compra character varying(20),
    imagen_1 bytea,
    imagen_2 bytea,
    CONSTRAINT partidas_cantidad_valida CHECK ((((cantidad >= (1)::double precision) AND (cantidad <= (99999)::double precision)) AND (cantidad = trunc(cantidad)))),
    CONSTRAINT partidas_imagen_1_check CHECK (((octet_length(imagen_1) >= 1) AND (octet_length(imagen_1) <= 2097152))),
    CONSTRAINT partidas_imagen_2_check CHECK (((octet_length(imagen_2) >= 1) AND (octet_length(imagen_2) <= 2097152))),
    CONSTRAINT partidas_precios_validos CHECK ((((precio_unitario_compra >= (0.01)::double precision) AND (precio_unitario_compra <= (9999999.99)::double precision)) AND ((precio_unitario_venta >= precio_unitario_compra) AND (precio_unitario_venta <= (9999999.99)::double precision)) AND (precio_unitario_compra = (round((precio_unitario_compra)::numeric, 2))::double precision) AND (precio_unitario_venta = (round((precio_unitario_venta)::numeric, 2))::double precision)))
);


--
-- Name: partidas_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.partidas_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: partidas_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.partidas_id_seq OWNED BY public.partidas.id;


--
-- Name: perfiles_cuenta; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.perfiles_cuenta (
    user_id bigint NOT NULL,
    tipo character varying(7) NOT NULL,
    comercial character varying(53) NOT NULL,
    razon_social character varying(38) DEFAULT ''::character varying NOT NULL,
    rfc character varying(13) DEFAULT ''::character varying NOT NULL,
    telefono character varying(10) DEFAULT ''::character varying NOT NULL,
    direccion character varying(40) DEFAULT ''::character varying NOT NULL,
    logo bytea,
    logo_tipo character varying(20) DEFAULT ''::character varying NOT NULL,
    CONSTRAINT perfiles_cuenta_check CHECK (((((tipo)::text = 'Empresa'::text) AND ((char_length(btrim((razon_social)::text)) >= 2) AND (char_length(btrim((razon_social)::text)) <= 150))) OR (((tipo)::text = 'Persona'::text) AND ((razon_social)::text = ''::text)))),
    CONSTRAINT perfiles_cuenta_comercial_check CHECK (((char_length(btrim((comercial)::text)) >= 2) AND (char_length(btrim((comercial)::text)) <= 100))),
    CONSTRAINT perfiles_cuenta_logo_check CHECK ((octet_length(logo) <= 2097152)),
    CONSTRAINT perfiles_cuenta_telefono_check CHECK ((((telefono)::text = ''::text) OR ((telefono)::text ~ '^[0-9]{10}$'::text))),
    CONSTRAINT perfiles_cuenta_tipo_check CHECK (((tipo)::text = ANY ((ARRAY['Empresa'::character varying, 'Persona'::character varying])::text[])))
);


--
-- Name: recuperacion_contrasena; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.recuperacion_contrasena (
    user_id bigint NOT NULL,
    solicitud_hash bytea NOT NULL,
    codigo_hash bytea,
    permiso_hash bytea,
    clave_base bytea NOT NULL,
    intentos smallint DEFAULT 0 NOT NULL,
    expira_en timestamp with time zone NOT NULL,
    permiso_expira_en timestamp with time zone,
    CONSTRAINT recuperacion_contrasena_check CHECK (((permiso_hash IS NULL) = (permiso_expira_en IS NULL))),
    CONSTRAINT recuperacion_contrasena_intentos_check CHECK (((intentos >= 0) AND (intentos <= 5)))
);


--
-- Name: recuperacion_envios; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.recuperacion_envios (
    correo_hash bytea NOT NULL,
    envios smallint NOT NULL,
    ultimo_envio timestamp with time zone NOT NULL,
    reenviar_desde timestamp with time zone NOT NULL,
    CONSTRAINT recuperacion_envios_envios_check CHECK (((envios >= 1) AND (envios <= 4)))
);


--
-- Name: users; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.users (
    id bigint NOT NULL,
    nombre character varying(60) NOT NULL,
    email character varying(100) NOT NULL,
    password_hash text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    dias_alerta_vencimiento smallint DEFAULT 10 NOT NULL,
    foto_perfil bytea,
    foto_perfil_tipo character varying(10),
    moneda_cotizacion character varying(3) DEFAULT 'MXN'::character varying NOT NULL,
    vigencia_cotizacion_dias smallint,
    color_documento_cotizacion character varying(7) DEFAULT '#1b4ed8'::character varying NOT NULL,
    fuente_documento_cotizacion character varying(12) DEFAULT 'arial'::character varying NOT NULL,
    CONSTRAINT users_color_documento_cotizacion_check CHECK (((color_documento_cotizacion)::text ~ '^#[0-9a-f]{6}$'::text)),
    CONSTRAINT users_dias_alerta_vencimiento_check CHECK (((dias_alerta_vencimiento >= 0) AND (dias_alerta_vencimiento <= 365))),
    CONSTRAINT users_foto_perfil_valida CHECK ((((foto_perfil IS NULL) AND (foto_perfil_tipo IS NULL)) OR ((foto_perfil IS NOT NULL) AND (foto_perfil_tipo IS NOT NULL) AND ((octet_length(foto_perfil) >= 1) AND (octet_length(foto_perfil) <= 2097152)) AND ((foto_perfil_tipo)::text = ANY ((ARRAY['image/jpeg'::character varying, 'image/png'::character varying])::text[]))))),
    CONSTRAINT users_fuente_documento_cotizacion_check CHECK (((fuente_documento_cotizacion)::text = ANY ((ARRAY['arial'::character varying, 'verdana'::character varying, 'georgia'::character varying, 'times'::character varying])::text[]))),
    CONSTRAINT users_moneda_cotizacion_check CHECK (((moneda_cotizacion)::text = ANY ((ARRAY['MXN'::character varying, 'USD'::character varying])::text[]))),
    CONSTRAINT users_vigencia_cotizacion_dias_check CHECK (((vigencia_cotizacion_dias >= 1) AND (vigencia_cotizacion_dias <= 365)))
);


--
-- Name: registro_emails; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.registro_emails AS
 SELECT lower(btrim((email)::text)) AS email
   FROM public.users;


--
-- Name: users_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.users_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: users_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.users_id_seq OWNED BY public.users.id;


--
-- Name: clientes id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.clientes ALTER COLUMN id SET DEFAULT nextval('public.clientes_id_seq'::regclass);


--
-- Name: cotizaciones id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.cotizaciones ALTER COLUMN id SET DEFAULT nextval('public.cotizaciones_id_seq'::regclass);


--
-- Name: partidas id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.partidas ALTER COLUMN id SET DEFAULT nextval('public.partidas_id_seq'::regclass);


--
-- Name: users id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users ALTER COLUMN id SET DEFAULT nextval('public.users_id_seq'::regclass);


--
-- Name: auth_sessions auth_sessions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.auth_sessions
    ADD CONSTRAINT auth_sessions_pkey PRIMARY KEY (token_hash);


--
-- Name: clientes clientes_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.clientes
    ADD CONSTRAINT clientes_pkey PRIMARY KEY (id);


--
-- Name: cotizaciones cotizaciones_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.cotizaciones
    ADD CONSTRAINT cotizaciones_pkey PRIMARY KEY (id);


--
-- Name: documentos_cotizacion documentos_cotizacion_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.documentos_cotizacion
    ADD CONSTRAINT documentos_cotizacion_pkey PRIMARY KEY (cotizacion_id);


--
-- Name: eliminacion_cuenta eliminacion_cuenta_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.eliminacion_cuenta
    ADD CONSTRAINT eliminacion_cuenta_pkey PRIMARY KEY (user_id);


--
-- Name: historial_nombre_usuario historial_nombre_usuario_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.historial_nombre_usuario
    ADD CONSTRAINT historial_nombre_usuario_pkey PRIMARY KEY (id);


--
-- Name: historial_perfil_comercial historial_perfil_comercial_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.historial_perfil_comercial
    ADD CONSTRAINT historial_perfil_comercial_pkey PRIMARY KEY (id);


--
-- Name: partidas partidas_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.partidas
    ADD CONSTRAINT partidas_pkey PRIMARY KEY (id);


--
-- Name: perfiles_cuenta perfiles_cuenta_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.perfiles_cuenta
    ADD CONSTRAINT perfiles_cuenta_pkey PRIMARY KEY (user_id);


--
-- Name: recuperacion_contrasena recuperacion_contrasena_permiso_hash_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.recuperacion_contrasena
    ADD CONSTRAINT recuperacion_contrasena_permiso_hash_key UNIQUE (permiso_hash);


--
-- Name: recuperacion_contrasena recuperacion_contrasena_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.recuperacion_contrasena
    ADD CONSTRAINT recuperacion_contrasena_pkey PRIMARY KEY (user_id);


--
-- Name: recuperacion_contrasena recuperacion_contrasena_solicitud_hash_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.recuperacion_contrasena
    ADD CONSTRAINT recuperacion_contrasena_solicitud_hash_key UNIQUE (solicitud_hash);


--
-- Name: recuperacion_envios recuperacion_envios_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.recuperacion_envios
    ADD CONSTRAINT recuperacion_envios_pkey PRIMARY KEY (correo_hash);


--
-- Name: users users_email_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_email_key UNIQUE (email);


--
-- Name: users users_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_pkey PRIMARY KEY (id);


--
-- Name: auth_sessions_user_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX auth_sessions_user_idx ON public.auth_sessions USING btree (user_id);


--
-- Name: clientes_identidad_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX clientes_identidad_idx ON public.clientes USING btree (owner_id, lower(btrim((nombre_comercial)::text)), upper(btrim((rfc)::text)));


--
-- Name: clientes_owner_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX clientes_owner_idx ON public.clientes USING btree (owner_id);


--
-- Name: cotizaciones_owner_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX cotizaciones_owner_idx ON public.cotizaciones USING btree (owner_id);


--
-- Name: historial_nombre_usuario_ultimo_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX historial_nombre_usuario_ultimo_idx ON public.historial_nombre_usuario USING btree (user_id, cambiado_en DESC);


--
-- Name: historial_perfil_comercial_ultimo_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX historial_perfil_comercial_ultimo_idx ON public.historial_perfil_comercial USING btree (user_id, cambiado_en DESC);


--
-- Name: idx_cotizaciones_owner_vigencia; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_cotizaciones_owner_vigencia ON public.cotizaciones USING btree (owner_id, vigencia_hasta, id) WHERE ((estado)::text <> 'Eliminada'::text);


--
-- Name: idx_partidas_cotizacion; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_partidas_cotizacion ON public.partidas USING btree (cotizacion_id);


--
-- Name: idx_users_email_normalizado; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_users_email_normalizado ON public.users USING btree (lower(btrim((email)::text)));


--
-- Name: recuperacion_envios_ultimo_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX recuperacion_envios_ultimo_idx ON public.recuperacion_envios USING btree (ultimo_envio);


--
-- Name: users_email_normalizado_unique; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX users_email_normalizado_unique ON public.users USING btree (lower(btrim((email)::text)));


--
-- Name: perfiles_cuenta perfiles_cuenta_registrar_cambio; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER perfiles_cuenta_registrar_cambio BEFORE UPDATE OF tipo, comercial, razon_social, rfc, telefono, direccion ON public.perfiles_cuenta FOR EACH ROW WHEN ((((((((old.tipo)::text IS DISTINCT FROM (new.tipo)::text) OR ((old.comercial)::text IS DISTINCT FROM (new.comercial)::text)) OR ((old.razon_social)::text IS DISTINCT FROM (new.razon_social)::text)) OR ((old.rfc)::text IS DISTINCT FROM (new.rfc)::text)) OR ((old.telefono)::text IS DISTINCT FROM (new.telefono)::text)) OR ((old.direccion)::text IS DISTINCT FROM (new.direccion)::text))) EXECUTE FUNCTION public.registrar_cambio_perfil_comercial();


--
-- Name: users users_registrar_cambio_nombre; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER users_registrar_cambio_nombre BEFORE UPDATE OF nombre ON public.users FOR EACH ROW WHEN (((old.nombre)::text IS DISTINCT FROM (new.nombre)::text)) EXECUTE FUNCTION public.registrar_cambio_nombre_usuario();


--
-- Name: auth_sessions auth_sessions_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.auth_sessions
    ADD CONSTRAINT auth_sessions_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- Name: clientes clientes_owner_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.clientes
    ADD CONSTRAINT clientes_owner_id_fkey FOREIGN KEY (owner_id) REFERENCES public.users(id);


--
-- Name: cotizaciones cotizaciones_owner_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.cotizaciones
    ADD CONSTRAINT cotizaciones_owner_id_fkey FOREIGN KEY (owner_id) REFERENCES public.users(id);


--
-- Name: documentos_cotizacion documentos_cotizacion_cotizacion_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.documentos_cotizacion
    ADD CONSTRAINT documentos_cotizacion_cotizacion_id_fkey FOREIGN KEY (cotizacion_id) REFERENCES public.cotizaciones(id) ON DELETE CASCADE;


--
-- Name: eliminacion_cuenta eliminacion_cuenta_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.eliminacion_cuenta
    ADD CONSTRAINT eliminacion_cuenta_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- Name: historial_nombre_usuario historial_nombre_usuario_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.historial_nombre_usuario
    ADD CONSTRAINT historial_nombre_usuario_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id);


--
-- Name: historial_perfil_comercial historial_perfil_comercial_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.historial_perfil_comercial
    ADD CONSTRAINT historial_perfil_comercial_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.perfiles_cuenta(user_id);


--
-- Name: partidas partidas_cotizacion_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.partidas
    ADD CONSTRAINT partidas_cotizacion_id_fkey FOREIGN KEY (cotizacion_id) REFERENCES public.cotizaciones(id) ON DELETE CASCADE;


--
-- Name: perfiles_cuenta perfiles_cuenta_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.perfiles_cuenta
    ADD CONSTRAINT perfiles_cuenta_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- Name: recuperacion_contrasena recuperacion_contrasena_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.recuperacion_contrasena
    ADD CONSTRAINT recuperacion_contrasena_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- PostgreSQL database dump complete
--

\unrestrict 0NrES0Mc3kfSYQWuOnxd6znHguogT7xzD2imfSrA9uYJSkN2NGljcc8luD6wn1q

