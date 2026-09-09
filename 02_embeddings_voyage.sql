-- Generación de embeddings (Voyage AI) y búsqueda semántica (pgvector).
-- La clave de Voyage se lee de Vault en el momento de la llamada
-- (vault.decrypted_secrets, nombre 'voyage_api_key'); nunca se guarda en código.

CREATE OR REPLACE FUNCTION public.generar_embedding_voyage(texto text)
 RETURNS vector
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'extensions', 'public', 'vault'
AS $function$
declare
  respuesta extensions.http_response;
  cuerpo jsonb;
  embedding_json jsonb;
begin
  select * into respuesta from extensions.http((
    'POST',
    'https://api.voyageai.com/v1/embeddings',
    ARRAY[extensions.http_header(
        'Authorization',
        'Bearer ' || (select decrypted_secret from vault.decrypted_secrets where name = 'voyage_api_key')
    )],
    'application/json',
    jsonb_build_object('input', ARRAY[texto], 'model', 'voyage-4-lite', 'output_dimension', 1024)::text
  )::extensions.http_request);

  if respuesta.status <> 200 then
    raise exception 'Error de Voyage AI (status %): %', respuesta.status, respuesta.content;
  end if;

  cuerpo := respuesta.content::jsonb;
  embedding_json := cuerpo -> 'data' -> 0 -> 'embedding';
  return (select array_agg(x::float4) from jsonb_array_elements_text(embedding_json) as x)::vector;
end;
$function$
;

CREATE OR REPLACE FUNCTION public.generar_embeddings_voyage_lote(textos text[])
 RETURNS vector[]
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'extensions', 'public', 'vault'
AS $function$
declare
  respuesta extensions.http_response;
  cuerpo jsonb;
  resultado vector[];
begin
  select * into respuesta from extensions.http((
    'POST',
    'https://api.voyageai.com/v1/embeddings',
    ARRAY[extensions.http_header(
        'Authorization',
        'Bearer ' || (select decrypted_secret from vault.decrypted_secrets where name = 'voyage_api_key')
    )],
    'application/json',
    jsonb_build_object('input', textos, 'model', 'voyage-4-lite', 'output_dimension', 1024)::text
  )::extensions.http_request);

  if respuesta.status <> 200 then
    raise exception 'Error de Voyage AI (status %): %', respuesta.status, respuesta.content;
  end if;

  cuerpo := respuesta.content::jsonb;

  select array_agg(
    (select array_agg(x::float4) from jsonb_array_elements_text(elem -> 'embedding') as x)::vector
    order by (elem ->> 'index')::int
  )
  into resultado
  from jsonb_array_elements(cuerpo -> 'data') as elem;

  return resultado;
end;
$function$
;

-- Búsqueda por similitud de coseno, restringida a fragmentos ya aprobados
-- (estado = 'activo'): el buscador nunca puede devolver contenido sin revisar.
CREATE OR REPLACE FUNCTION public.buscar_fragmentos_similares(embedding_consulta vector, cantidad integer DEFAULT 3)
 RETURNS TABLE(id uuid, tema text, contenido text, fuente text, similitud double precision)
 LANGUAGE sql
 STABLE
AS $function$
  select id, tema, contenido, fuente, 1 - (embedding <=> embedding_consulta) as similitud
  from fragmentos_conocimiento
  where estado = 'activo' and embedding is not null
  order by embedding <=> embedding_consulta
  limit cantidad;
$function$
;
