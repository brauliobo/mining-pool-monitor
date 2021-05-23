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
-- Name: intervals; Type: VIEW; Schema: public; Owner: braulio
--

CREATE VIEW public.intervals AS
 SELECT (start_date.start_date)::date AS start_date,
    ((start_date.start_date + '1 day'::interval))::date AS end_date,
    row_number() OVER (ORDER BY start_date.start_date DESC) AS seq
   FROM generate_series((now() - '9 days'::interval), now(), '1 day'::interval) start_date(start_date)
  WHERE (((start_date.start_date + '1 day'::interval))::date <= now())
  ORDER BY ((start_date.start_date)::date) DESC;


ALTER TABLE public.intervals OWNER TO braulio;

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
   FROM ((public.wallet_reads p
     JOIN public.wallet_reads p2 ON (((p2.pool = p.pool) AND (p2.wallet = p.wallet) AND (p2.balance > p.balance) AND ((5)::double precision > ((100)::double precision * abs(((p2.reported_hashrate / p.reported_hashrate) - (1)::double precision)))))))
     JOIN public.intervals i ON ((((p.read_at)::date = i.start_date) AND ((p2.read_at)::date = i.end_date) AND ((75)::double precision > ((100)::double precision * abs((((date_part('epoch'::text, (p2.read_at - p.read_at)) / (3600)::double precision) / (24)::double precision) - (1)::double precision)))))));


ALTER TABLE public.wallet_pairs OWNER TO braulio;

--
-- Name: ordered_wallet_pairs; Type: VIEW; Schema: public; Owner: braulio
--

CREATE VIEW public.ordered_wallet_pairs AS
 SELECT row_number() OVER (PARTITION BY wp.pool, wp.wallet, wp.iseq ORDER BY wp.pool, wp.wallet, wp.iseq, (abs(((wp.hours / (wp.period)::double precision) - (1)::double precision))), wp.second_read DESC) AS "row",
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
    wp.second_read
   FROM public.wallet_pairs wp;


ALTER TABLE public.ordered_wallet_pairs OWNER TO braulio;

--
-- Name: periods; Type: VIEW; Schema: public; Owner: braulio
--

CREATE VIEW public.periods AS
 SELECT ordered_wallet_pairs.pool,
    ordered_wallet_pairs.wallet,
    ordered_wallet_pairs.period,
    ordered_wallet_pairs.iseq,
    (round(ordered_wallet_pairs.hashrate))::integer AS "MH",
    round((ordered_wallet_pairs.hours)::numeric, 2) AS hours,
    round(((((100000)::double precision * ((24)::double precision / ordered_wallet_pairs.hours)) * (ordered_wallet_pairs.reward / ordered_wallet_pairs.hashrate)))::numeric, 2) AS eth_mh_day,
    round((ordered_wallet_pairs.reward)::numeric, 5) AS reward,
    round((ordered_wallet_pairs.first_balance)::numeric, 5) AS "1st_balance",
    round((ordered_wallet_pairs.second_balance)::numeric, 5) AS "2nd_balance",
    to_char(ordered_wallet_pairs.first_read, 'MM/DD HH24:MI'::text) AS "1st_read",
    to_char(ordered_wallet_pairs.second_read, 'MM/DD HH24:MI'::text) AS "2nd_read"
   FROM public.ordered_wallet_pairs
  WHERE (ordered_wallet_pairs."row" = 1);


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
    periods."1st_balance",
    periods."2nd_balance",
    periods."1st_read",
    periods."2nd_read"
   FROM public.periods
  WITH NO DATA;


ALTER TABLE public.periods_materialized OWNER TO braulio;

--
-- Name: rewards; Type: VIEW; Schema: public; Owner: braulio
--

CREATE VIEW public.rewards AS
 SELECT p.pool,
    p.wallet,
    idf.period,
    avg((p.hours * (id.seq)::numeric)) FILTER (WHERE (id.period <= (p.period * p.iseq))) AS hours,
    avg(p.eth_mh_day) FILTER (WHERE (id.period <= (p.period * p.iseq))) AS eth_mh_day
   FROM ((public.periods_materialized p
     JOIN public.intervals_defs id ON ((id.period <= (p.period * p.iseq))))
     JOIN public.intervals_defs idf ON ((idf.period = (p.period * p.iseq))))
  GROUP BY p.pool, p.wallet, idf.period
  ORDER BY p.pool, p.wallet, idf.period;


ALTER TABLE public.rewards OWNER TO braulio;

--
-- Name: pools; Type: VIEW; Schema: public; Owner: braulio
--

CREATE VIEW public.pools AS
 SELECT ((row_number() OVER (ORDER BY (avg(
        CASE
            WHEN (rewards.period = 216) THEN rewards.eth_mh_day
            ELSE NULL::numeric
        END)) DESC NULLS LAST) || '. '::text) || rewards.pool) AS pool,
    count(DISTINCT rewards.wallet) AS "TW",
    round(avg(
        CASE
            WHEN (rewards.period = 24) THEN rewards.eth_mh_day
            ELSE NULL::numeric
        END), 2) AS "1d",
    round(avg(
        CASE
            WHEN (rewards.period = 72) THEN rewards.eth_mh_day
            ELSE NULL::numeric
        END), 2) AS "3d",
    round(avg(
        CASE
            WHEN (rewards.period = 144) THEN rewards.eth_mh_day
            ELSE NULL::numeric
        END), 2) AS "6d",
    round(avg(
        CASE
            WHEN (rewards.period = 216) THEN rewards.eth_mh_day
            ELSE NULL::numeric
        END), 2) AS "9d"
   FROM public.rewards
  GROUP BY rewards.pool
  ORDER BY (avg(
        CASE
            WHEN (rewards.period = 216) THEN rewards.eth_mh_day
            ELSE NULL::numeric
        END)) DESC NULLS LAST;


ALTER TABLE public.pools OWNER TO braulio;

--
-- Name: wallets_tracked; Type: TABLE; Schema: public; Owner: braulio
--

CREATE TABLE public.wallets_tracked (
    coin text,
    pool text,
    wallet text,
    hashrate_last double precision,
    hashrate_avg_24h double precision,
    started_at timestamp without time zone DEFAULT now(),
    last_read_at timestamp without time zone
);


ALTER TABLE public.wallets_tracked OWNER TO braulio;

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

