--
-- PostgreSQL database dump
--

-- Dumped from database version 13.3
-- Dumped by pg_dump version 13.3

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
-- Name: tablefunc; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS tablefunc WITH SCHEMA public;


--
-- Name: EXTENSION tablefunc; Type: COMMENT; Schema: -; Owner: 
--

COMMENT ON EXTENSION tablefunc IS 'functions that manipulate whole tables, including crosstab';


--
-- Name: _final_median(numeric[]); Type: FUNCTION; Schema: public; Owner: braulio
--

CREATE FUNCTION public._final_median(numeric[]) RETURNS numeric
    LANGUAGE sql IMMUTABLE
    AS $_$
   SELECT AVG(val)
   FROM (
     SELECT val
     FROM unnest($1) val
     ORDER BY 1
     LIMIT  2 - MOD(array_upper($1, 1), 2)
     OFFSET CEIL(array_upper($1, 1) / 2.0) - 1
   ) sub;
$_$;


ALTER FUNCTION public._final_median(numeric[]) OWNER TO braulio;

--
-- Name: _final_median(anyarray); Type: FUNCTION; Schema: public; Owner: braulio
--

CREATE FUNCTION public._final_median(anyarray) RETURNS double precision
    LANGUAGE sql IMMUTABLE
    AS $_$ 
  WITH q AS
  (
     SELECT val
     FROM unnest($1) val
     WHERE VAL IS NOT NULL
     ORDER BY 1
  ),
  cnt AS
  (
    SELECT COUNT(*) as c FROM q
  )
  SELECT AVG(val)::float8
  FROM 
  (
    SELECT val FROM q
    LIMIT  2 - MOD((SELECT c FROM cnt), 2)
    OFFSET GREATEST(CEIL((SELECT c FROM cnt) / 2.0) - 1,0)  
  ) q2;
$_$;


ALTER FUNCTION public._final_median(anyarray) OWNER TO braulio;

--
-- Name: median(anyelement); Type: AGGREGATE; Schema: public; Owner: braulio
--

CREATE AGGREGATE public.median(anyelement) (
    SFUNC = array_append,
    STYPE = anyarray,
    INITCOND = '{}',
    FINALFUNC = public._final_median
);


ALTER AGGREGATE public.median(anyelement) OWNER TO braulio;

--
-- Name: median(numeric); Type: AGGREGATE; Schema: public; Owner: braulio
--

CREATE AGGREGATE public.median(numeric) (
    SFUNC = array_append,
    STYPE = numeric[],
    INITCOND = '{}',
    FINALFUNC = public._final_median
);


ALTER AGGREGATE public.median(numeric) OWNER TO braulio;

SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: coins; Type: TABLE; Schema: public; Owner: braulio
--

CREATE TABLE public.coins (
    coin character varying(5) NOT NULL,
    multiplier integer
);


ALTER TABLE public.coins OWNER TO braulio;

--
-- Name: intervals_defs; Type: TABLE; Schema: public; Owner: braulio
--

CREATE TABLE public.intervals_defs (
    period integer,
    label text,
    seq integer
);


ALTER TABLE public.intervals_defs OWNER TO braulio;

--
-- Name: intervals; Type: VIEW; Schema: public; Owner: braulio
--

CREATE VIEW public.intervals AS
 WITH initial_date AS (
         SELECT ((now() - ((( SELECT (max(intervals_defs.period) / 24)
                   FROM public.intervals_defs) || ' days'::text))::interval))::date AS d
        )
 SELECT (start_date.start_date)::date AS start_date,
    ((start_date.start_date + '1 day'::interval))::date AS end_date,
    row_number() OVER (ORDER BY start_date.start_date DESC) AS seq
   FROM initial_date,
    LATERAL generate_series((initial_date.d)::timestamp without time zone, (CURRENT_DATE - '1 day'::interval), '1 day'::interval) start_date(start_date)
  ORDER BY ((start_date.start_date)::date) DESC;


ALTER TABLE public.intervals OWNER TO braulio;

--
-- Name: wallet_reads; Type: TABLE; Schema: public; Owner: braulio
--

CREATE TABLE public.wallet_reads (
    coin text,
    pool text,
    wallet text,
    read_at timestamp without time zone,
    hashrate double precision,
    balance double precision
);


ALTER TABLE public.wallet_reads OWNER TO braulio;

--
-- Name: wallets_tracked; Type: TABLE; Schema: public; Owner: braulio
--

CREATE TABLE public.wallets_tracked (
    coin text NOT NULL,
    pool text NOT NULL,
    wallet text NOT NULL,
    hashrate_last double precision,
    hashrate_avg_24h double precision,
    started_at timestamp without time zone DEFAULT now(),
    last_read_at timestamp without time zone
);


ALTER TABLE public.wallets_tracked OWNER TO braulio;

--
-- Name: last_reads; Type: VIEW; Schema: public; Owner: braulio
--

CREATE VIEW public.last_reads AS
 SELECT row_number() OVER (PARTITION BY r.coin, r.pool, r.wallet, i.seq ORDER BY r2.read_at DESC, (abs((((date_part('epoch'::text, (r2.read_at - r.read_at)) / (3600)::double precision) / (24)::double precision) - (1)::double precision)))) AS "row",
    r.coin,
    r.pool,
    r.wallet,
    24 AS period,
    i.seq AS iseq,
    (date_part('epoch'::text, (r2.read_at - r.read_at)) / (3600)::double precision) AS hours,
    r.hashrate AS first_hashrate,
    r2.hashrate AS second_hashrate,
    r.balance AS first_balance,
    r2.balance AS second_balance,
    r.read_at AS first_read,
    r2.read_at AS second_read
   FROM (((public.wallet_reads r
     JOIN public.wallets_tracked t ON (((t.coin = r.coin) AND (t.pool = r.pool) AND (t.wallet = r.wallet) AND (t.hashrate_last > (0)::double precision) AND (t.last_read_at >= (now() - '24:00:00'::interval)))))
     JOIN public.wallet_reads r2 ON (((r2.coin = r.coin) AND (r2.pool = r.pool) AND (r2.wallet = r.wallet))))
     JOIN public.intervals i ON ((((r.read_at)::date = i.start_date) AND ((r2.read_at)::date = i.end_date) AND (((100)::double precision * abs((((date_part('epoch'::text, (r2.read_at - r.read_at)) / (3600)::double precision) / (24)::double precision) - (1)::double precision))) < (50)::double precision))));


ALTER TABLE public.last_reads OWNER TO braulio;

--
-- Name: wallet_rewards; Type: VIEW; Schema: public; Owner: braulio
--

CREATE VIEW public.wallet_rewards AS
 SELECT r.coin,
    r.pool,
    r.wallet,
    r.read_at,
    r.hashrate,
    r.balance,
    (r.balance - lag(r.balance) OVER (PARTITION BY r.pool, r.wallet ORDER BY r.read_at)) AS reward
   FROM public.wallet_reads r
  ORDER BY r.coin, r.pool, r.wallet, r.read_at DESC;


ALTER TABLE public.wallet_rewards OWNER TO braulio;

--
-- Name: wallet_pairs; Type: VIEW; Schema: public; Owner: braulio
--

CREATE VIEW public.wallet_pairs AS
 SELECT r."row",
    r.coin,
    r.pool,
    r.wallet,
    r.period,
    r.iseq,
    r.hours,
    r.first_hashrate,
    r.second_hashrate,
    r.first_balance,
    r.second_balance,
    r.first_read,
    r.second_read,
    avg(wr.hashrate) AS avg_hashrate,
    sum(wr.reward) AS reward
   FROM (public.last_reads r
     JOIN public.wallet_rewards wr ON (((wr.coin = r.coin) AND (wr.pool = r.pool) AND (wr.wallet = r.wallet) AND (wr.read_at >= r.first_read) AND (wr.read_at <= r.second_read) AND (wr.reward > ('-0.02'::numeric)::double precision))))
  WHERE (r."row" = 1)
  GROUP BY r."row", r.coin, r.pool, r.wallet, r.period, r.iseq, r.hours, r.first_hashrate, r.second_hashrate, r.first_balance, r.second_balance, r.first_read, r.second_read
  ORDER BY r.iseq, r.hours DESC, r.second_read DESC;


ALTER TABLE public.wallet_pairs OWNER TO braulio;

--
-- Name: periods; Type: VIEW; Schema: public; Owner: braulio
--

CREATE VIEW public.periods AS
 SELECT wp.coin,
    wp.pool,
    wp.wallet,
    wp.period,
    wp.iseq,
    (round(wp.avg_hashrate))::integer AS "MH",
    round((wp.hours)::numeric, 2) AS hours,
    round(((((c.multiplier)::double precision * ((24)::double precision / wp.hours)) * (wp.reward / wp.avg_hashrate)))::numeric, 2) AS eth_mh_day,
    round((wp.reward)::numeric, 5) AS reward,
    round((wp.first_balance)::numeric, 5) AS "1st balance",
    round((wp.second_balance)::numeric, 5) AS "2nd balance",
    to_char(wp.first_read, 'MM/DD HH24:MI'::text) AS "1st read",
    to_char(wp.second_read, 'MM/DD HH24:MI'::text) AS "2nd read"
   FROM (public.wallet_pairs wp
     JOIN public.coins c ON (((c.coin)::text = wp.coin)))
  WHERE ((((100)::double precision * abs(((wp.second_hashrate / wp.avg_hashrate) - (1)::double precision))) < (10)::double precision) AND (wp.avg_hashrate > (0)::double precision));


ALTER TABLE public.periods OWNER TO braulio;

--
-- Name: periods_materialized; Type: MATERIALIZED VIEW; Schema: public; Owner: braulio
--

CREATE MATERIALIZED VIEW public.periods_materialized AS
 SELECT periods.coin,
    periods.pool,
    periods.wallet,
    periods.period,
    periods.iseq,
    periods."MH",
    periods.hours,
    periods.eth_mh_day,
    periods.reward,
    periods."1st balance",
    periods."2nd balance",
    periods."1st read",
    periods."2nd read"
   FROM public.periods
  WITH NO DATA;


ALTER TABLE public.periods_materialized OWNER TO braulio;

--
-- Name: grouped_periods; Type: VIEW; Schema: public; Owner: braulio
--

CREATE VIEW public.grouped_periods AS
 SELECT pid.coin,
    pid.pool,
    pid.wallet,
    id.period,
    percentile_cont((0.5)::double precision) WITHIN GROUP (ORDER BY ((pid.eth_mh_day)::double precision)) AS eth_mh_day,
    avg(pid."MH") AS hashrate,
    sum(pid.hours) AS hours,
    sum(pid.reward) AS reward,
    min(pid.iseq) AS iseq_min,
    max(pid.iseq) AS iseq_max,
    count(DISTINCT pid.iseq) AS iseq_count
   FROM ((public.periods_materialized p
     JOIN public.intervals_defs id ON (true))
     JOIN public.periods_materialized pid ON (((pid.coin = p.coin) AND (pid.pool = p.pool) AND (pid.wallet = p.wallet) AND (id.period >= (pid.period * pid.iseq)))))
  GROUP BY pid.coin, pid.pool, pid.wallet, id.period
  ORDER BY pid.coin, pid.pool, pid.wallet, id.period;


ALTER TABLE public.grouped_periods OWNER TO braulio;

--
-- Name: rewards; Type: VIEW; Schema: public; Owner: braulio
--

CREATE VIEW public.rewards AS
 SELECT b.coin,
    b.pool,
    b.wallet,
    b.period,
    percentile_cont((0.5)::double precision) WITHIN GROUP (ORDER BY b.eth_mh_day) AS eth_mh_day
   FROM (public.grouped_periods b
     JOIN public.intervals_defs id ON ((id.period = b.period)))
  WHERE (((b.iseq_max = 1) AND (b.period = 24)) OR (((b.iseq_max)::double precision >= round((((id.seq * 2) / 3))::double precision)) AND ((b.iseq_count)::double precision >= round(((id.seq / 2))::double precision))))
  GROUP BY b.coin, b.pool, b.wallet, b.period
  ORDER BY b.coin, b.pool, b.wallet, b.period;


ALTER TABLE public.rewards OWNER TO braulio;

--
-- Name: coins coins_pkey; Type: CONSTRAINT; Schema: public; Owner: braulio
--

ALTER TABLE ONLY public.coins
    ADD CONSTRAINT coins_pkey PRIMARY KEY (coin);


--
-- Name: wallet_reads wallet_reads_unique_constraint; Type: CONSTRAINT; Schema: public; Owner: braulio
--

ALTER TABLE ONLY public.wallet_reads
    ADD CONSTRAINT wallet_reads_unique_constraint UNIQUE (coin, pool, wallet, read_at);


--
-- Name: wallets_tracked wallets_tracked_pkey; Type: CONSTRAINT; Schema: public; Owner: braulio
--

ALTER TABLE ONLY public.wallets_tracked
    ADD CONSTRAINT wallets_tracked_pkey PRIMARY KEY (coin, pool, wallet);


--
-- Name: wallets_tracked wallets_tracked_unique_constraint; Type: CONSTRAINT; Schema: public; Owner: braulio
--

ALTER TABLE ONLY public.wallets_tracked
    ADD CONSTRAINT wallets_tracked_unique_constraint UNIQUE (coin, pool, wallet);


--
-- Name: wallet_reads_all_index; Type: INDEX; Schema: public; Owner: braulio
--

CREATE INDEX wallet_reads_all_index ON public.wallet_reads USING btree (pool, wallet, balance, read_at, hashrate);


--
-- Name: wallets_tracked_all_index; Type: INDEX; Schema: public; Owner: braulio
--

CREATE INDEX wallets_tracked_all_index ON public.wallets_tracked USING btree (coin, pool, wallet, hashrate_last, hashrate_avg_24h);


--
-- PostgreSQL database dump complete
--

