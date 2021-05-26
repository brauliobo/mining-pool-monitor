--
-- PostgreSQL database dump
--

-- Dumped from database version 13.2
-- Dumped by pg_dump version 13.2

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
    reported_hashrate double precision,
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
-- Name: wallet_pairs; Type: VIEW; Schema: public; Owner: braulio
--

CREATE VIEW public.wallet_pairs AS
 SELECT p.pool,
    p.wallet,
    i.seq AS iseq,
    24 AS period,
    (date_part('epoch'::text, (p2.read_at - p.read_at)) / (3600)::double precision) AS hours,
    ((p.reported_hashrate + p2.reported_hashrate) / (2)::double precision) AS hashrate,
    (p2.balance - p.balance) AS reward,
    p.balance AS first_balance,
    p2.balance AS second_balance,
    p.read_at AS first_read,
    p2.read_at AS second_read
   FROM (((public.wallet_reads p
     JOIN public.wallets_tracked pt ON (((pt.pool = p.pool) AND (pt.wallet = p.wallet) AND (pt.hashrate_last > (0)::double precision))))
     JOIN public.wallet_reads p2 ON (((p2.pool = p.pool) AND (p2.wallet = p.wallet) AND (p2.balance > p.balance))))
     JOIN public.intervals i ON ((((p.read_at)::date = i.start_date) AND ((p2.read_at)::date = i.end_date) AND (((100)::double precision * abs((((date_part('epoch'::text, (p2.read_at - p.read_at)) / (3600)::double precision) / (24)::double precision) - (1)::double precision))) < (75)::double precision))));


ALTER TABLE public.wallet_pairs OWNER TO braulio;

--
-- Name: filtered_wallet_pairs; Type: VIEW; Schema: public; Owner: braulio
--

CREATE VIEW public.filtered_wallet_pairs AS
 SELECT DISTINCT wp."row",
    wp.pool,
    wp.wallet,
    wp.iseq,
    wp.period,
    wp.hours,
    wp.hashrate,
    wp.reward,
    wp.first_balance,
    wp.second_balance,
    wp.first_read,
    wp.second_read,
    avg(wr.reported_hashrate) FILTER (WHERE ((wr.read_at >= wp.first_read) AND (wr.read_at <= wp.second_read))) OVER (PARTITION BY wr.pool, wr.wallet, wp.iseq) AS avg_hashrate
   FROM (( SELECT row_number() OVER (PARTITION BY wp_1.pool, wp_1.wallet, wp_1.iseq ORDER BY wp_1.second_read DESC, (abs(((wp_1.hours / (wp_1.period)::double precision) - (1)::double precision)))) AS "row",
            wp_1.pool,
            wp_1.wallet,
            wp_1.iseq,
            wp_1.period,
            wp_1.hours,
            wp_1.hashrate,
            wp_1.reward,
            wp_1.first_balance,
            wp_1.second_balance,
            wp_1.first_read,
            wp_1.second_read
           FROM public.wallet_pairs wp_1) wp
     JOIN public.wallet_reads wr ON (((wp.pool = wr.pool) AND (wp.wallet = wr.wallet))))
  WHERE (wp."row" = 1);


ALTER TABLE public.filtered_wallet_pairs OWNER TO braulio;

--
-- Name: periods; Type: VIEW; Schema: public; Owner: braulio
--

CREATE VIEW public.periods AS
 SELECT filtered_wallet_pairs.pool,
    filtered_wallet_pairs.wallet,
    filtered_wallet_pairs.period,
    filtered_wallet_pairs.iseq,
    (round(filtered_wallet_pairs.avg_hashrate))::integer AS "MH",
    round((filtered_wallet_pairs.hours)::numeric, 2) AS hours,
    round(((((100000)::double precision * ((24)::double precision / filtered_wallet_pairs.hours)) * (filtered_wallet_pairs.reward / filtered_wallet_pairs.avg_hashrate)))::numeric, 2) AS eth_mh_day,
    round((filtered_wallet_pairs.reward)::numeric, 5) AS reward,
    round((filtered_wallet_pairs.first_balance)::numeric, 5) AS "1st balance",
    round((filtered_wallet_pairs.second_balance)::numeric, 5) AS "2nd balance",
    to_char(filtered_wallet_pairs.first_read, 'MM/DD HH24:MI'::text) AS "1st read",
    to_char(filtered_wallet_pairs.second_read, 'MM/DD HH24:MI'::text) AS "2nd read"
   FROM public.filtered_wallet_pairs
  WHERE (((100)::double precision * abs(((filtered_wallet_pairs.hashrate / filtered_wallet_pairs.avg_hashrate) - (1)::double precision))) < (5)::double precision);


ALTER TABLE public.periods OWNER TO braulio;

--
-- Name: periods_materialized; Type: MATERIALIZED VIEW; Schema: public; Owner: braulio
--

CREATE MATERIALIZED VIEW public.periods_materialized AS
 SELECT periods.pool,
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
-- Name: rewards; Type: VIEW; Schema: public; Owner: braulio
--

CREATE VIEW public.rewards AS
 SELECT pid.pool,
    pid.wallet,
    id.period,
    avg((pid.hours * (id.seq)::numeric)) AS hours,
    avg(pid.eth_mh_day) AS eth_mh_day
   FROM ((public.periods_materialized p
     JOIN public.intervals_defs id ON (true))
     JOIN public.periods_materialized pid ON (((pid.pool = p.pool) AND (pid.wallet = p.wallet) AND (id.period >= (pid.period * pid.iseq)))))
  GROUP BY pid.pool, pid.wallet, id.period
  ORDER BY pid.pool, pid.wallet, id.period;


ALTER TABLE public.rewards OWNER TO braulio;

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
-- Name: wallets_all_index; Type: INDEX; Schema: public; Owner: braulio
--

CREATE INDEX wallets_all_index ON public.wallet_reads USING btree (pool, wallet, balance, read_at, reported_hashrate);


--
-- Name: wallets_tracked_all_index; Type: INDEX; Schema: public; Owner: braulio
--

CREATE INDEX wallets_tracked_all_index ON public.wallets_tracked USING btree (coin, pool, wallet, hashrate_last, hashrate_avg_24h);


--
-- PostgreSQL database dump complete
--

