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
-- Name: wallets; Type: TABLE; Schema: public; Owner: braulio
--

CREATE TABLE public.wallets (
    coin text,
    pool text,
    wallet text,
    read_at timestamp without time zone,
    reported_hashrate double precision,
    balance double precision
);


ALTER TABLE public.wallets OWNER TO braulio;

--
-- Name: periods; Type: VIEW; Schema: public; Owner: braulio
--

CREATE VIEW public.periods AS
 WITH wallet_pairs AS (
         SELECT row_number() OVER (PARTITION BY p.pool, p.wallet, (floor(((date_part('epoch'::text, (p2.read_at - p.read_at)) / (3600)::double precision) / (24)::double precision))), i.seq ORDER BY p.pool, p.wallet, p.read_at DESC) AS "row",
            p.pool,
            p.wallet,
            i.seq AS iseq,
            (floor(((date_part('epoch'::text, (p2.read_at - p.read_at)) / (3600)::double precision) / (24)::double precision)) * (24)::double precision) AS period,
            (date_part('epoch'::text, (p2.read_at - p.read_at)) / (3600)::double precision) AS hours,
            ((p.reported_hashrate + p2.reported_hashrate) / (2)::double precision) AS hashrate,
            (p2.balance - p.balance) AS reward,
            p.balance AS first_balance,
            p2.balance AS second_balance,
            p.read_at AS first_read,
            p2.read_at AS second_read
           FROM ((public.wallets p
             JOIN public.wallets p2 ON (((p2.pool = p.pool) AND (p2.wallet = p.wallet) AND (p2.balance > p.balance) AND ((5)::double precision > (((100)::double precision * abs((p2.reported_hashrate - p.reported_hashrate))) / p.reported_hashrate)))))
             JOIN public.intervals i ON ((((p.read_at)::date = i.start_date) AND ((p2.read_at)::date = i.end_date) AND ((floor(((date_part('epoch'::text, (p2.read_at - p.read_at)) / (3600)::double precision) / (24)::double precision)) * (24)::double precision) = (24)::double precision))))
        )
 SELECT wallet_pairs.pool,
    wallet_pairs.wallet,
    wallet_pairs.period,
    wallet_pairs.iseq,
    (round(wallet_pairs.hashrate))::integer AS "MH",
    round((wallet_pairs.hours)::numeric, 2) AS hours,
    round(((((100000)::double precision * ((24)::double precision / wallet_pairs.hours)) * (wallet_pairs.reward / wallet_pairs.hashrate)))::numeric, 2) AS eth_mh_day,
    round((wallet_pairs.reward)::numeric, 5) AS reward,
    round((wallet_pairs.first_balance)::numeric, 5) AS "1st_balance",
    round((wallet_pairs.second_balance)::numeric, 5) AS "2nd_balance",
    to_char(wallet_pairs.first_read, 'MM/DD HH24:MI'::text) AS "1st_read",
    to_char(wallet_pairs.second_read, 'MM/DD HH24:MI'::text) AS "2nd_read"
   FROM wallet_pairs
  WHERE (wallet_pairs."row" = 1);


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
    id.period,
    avg((p.hours * (id.seq)::numeric)) FILTER (WHERE (p.iseq <= id.seq)) AS hours,
    avg(p.eth_mh_day) FILTER (WHERE (p.iseq <= id.seq)) AS eth_mh_day
   FROM (public.periods_materialized p
     JOIN public.intervals_defs id ON ((p.iseq <= id.seq)))
  GROUP BY p.pool, p.wallet, id.period
  ORDER BY p.pool, p.wallet, id.period;


ALTER TABLE public.rewards OWNER TO braulio;

--
-- Name: pools; Type: VIEW; Schema: public; Owner: braulio
--

CREATE VIEW public.pools AS
 SELECT rewards.pool,
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
  ORDER BY (round(avg(
        CASE
            WHEN (rewards.period = 216) THEN rewards.eth_mh_day
            ELSE NULL::numeric
        END), 2)) DESC NULLS LAST, (round(avg(
        CASE
            WHEN (rewards.period = 144) THEN rewards.eth_mh_day
            ELSE NULL::numeric
        END), 2)) DESC NULLS LAST, (round(avg(
        CASE
            WHEN (rewards.period = 72) THEN rewards.eth_mh_day
            ELSE NULL::numeric
        END), 2)) DESC NULLS LAST, (round(avg(
        CASE
            WHEN (rewards.period = 24) THEN rewards.eth_mh_day
            ELSE NULL::numeric
        END), 2)) DESC NULLS LAST;


ALTER TABLE public.pools OWNER TO braulio;

--
-- Name: wallets_all_index; Type: INDEX; Schema: public; Owner: braulio
--

CREATE INDEX wallets_all_index ON public.wallets USING btree (pool, wallet, balance, read_at, reported_hashrate);


--
-- PostgreSQL database dump complete
--

