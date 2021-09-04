update wallet_reads
set pair_24h = json_build_object('{last}', 'null')
where (pair_24h->'last')::boolean IS FALSE;

delete from intervals_defs;
insert into intervals_defs(period,label,seq) values (24,'24h',1), (3*24,'3d',3), (7*24,'1w',7), (14*24,'2w',14), (21*24,'3w',21);;

