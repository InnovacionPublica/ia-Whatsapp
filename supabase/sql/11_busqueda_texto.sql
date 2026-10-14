-- Búsqueda por texto en español (sin acentos, con raíces de palabras) como
-- reemplazo de la búsqueda semántica con embeddings (Voyage), decidido el
-- 14 de octubre de 2026. Es aditiva: no toca la columna embedding ni la
-- función buscar_fragmentos_similares, que quedan disponibles por si se
-- quisiera volver a la búsqueda semántica.

create text search configuration public.es_sin_acentos (copy = pg_catalog.spanish);
alter text search configuration public.es_sin_acentos
  alter mapping for hword, hword_part, word
  with extensions.unaccent, pg_catalog.spanish_stem;

alter table public.fragmentos_conocimiento
  add column busqueda tsvector generated always as (
    setweight(to_tsvector('public.es_sin_acentos'::regconfig, coalesce(tema, '')), 'A') ||
    setweight(to_tsvector('public.es_sin_acentos'::regconfig, coalesce(preguntas_frecuentes, '')), 'A') ||
    setweight(to_tsvector('public.es_sin_acentos'::regconfig, coalesce(contenido, '')), 'B') ||
    setweight(to_tsvector('public.es_sin_acentos'::regconfig, coalesce(informacion_adicional, '')), 'C')
  ) stored;

create index fragmentos_conocimiento_busqueda_idx
  on public.fragmentos_conocimiento using gin (busqueda);

-- Puntaje (0 a 1) = peso de los términos de la consulta que aparecen en el
-- fragmento, sobre el peso total de los términos de la consulta. Los términos
-- poco frecuentes en la base pesan más; los que no existen en ninguna parte
-- cuentan en el denominador (criterio conservador: ante palabras desconocidas,
-- baja la confianza). Se ignoran palabras de cortesía o relleno. Se exige un
-- mínimo de evidencia: al menos 2 términos coincidentes (o 1 si la consulta
-- tiene uno solo) y un peso informativo mínimo de 2.5.
create or replace function public.buscar_fragmentos_texto(consulta text, cantidad integer default 3)
 returns table(id uuid, tema text, contenido text, fuente text, similitud double precision)
 language sql
 stable
 set search_path to 'public', 'extensions', 'pg_catalog'
as $function$
  with
  n as (
    select count(*)::float8 as total
    from fragmentos_conocimiento where estado = 'activo'
  ),
  terminos as (
    select distinct lexema
    from unnest(tsvector_to_array(
      to_tsvector('public.es_sin_acentos'::regconfig, coalesce(consulta, '')))) as lexema
    where lexema <> all (array[
      'hol','buen','dia','dias','tard','noch','quier','quis','necesit','graci','favor',
      'consult','inform','informacion','ayud','pued','podr','gust'
    ])
  ),
  pesos as (
    select t.lexema,
           ln(1 + (select total from n) / greatest((
             select count(*) from fragmentos_conocimiento f
             where f.estado = 'activo' and t.lexema = any(tsvector_to_array(f.busqueda))
           ), 1)::float8) as peso
    from terminos t
  ),
  puntaje as (
    select f.id, f.tema, f.contenido, f.fuente,
           coalesce(sum(p.peso) filter (where p.lexema = any(tsvector_to_array(f.busqueda))), 0) as peso_coincidente,
           count(*) filter (where p.lexema = any(tsvector_to_array(f.busqueda))) as coinciden,
           (select sum(peso) from pesos) as peso_total,
           (select count(*) from pesos) as total_terminos
    from fragmentos_conocimiento f
    cross join pesos p
    where f.estado = 'activo'
    group by f.id, f.tema, f.contenido, f.fuente, f.busqueda
  )
  select id, tema, contenido, fuente,
         (peso_coincidente / nullif(peso_total, 0))::float8 as similitud
  from puntaje
  where coinciden >= least(2, total_terminos)
    and peso_coincidente >= 2.5
  order by similitud desc
  limit cantidad;
$function$;

revoke all on function public.buscar_fragmentos_texto(text, integer) from public, anon, authenticated;
