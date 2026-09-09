-- Generación de la respuesta final con Claude (Anthropic), a partir de un
-- mensaje de sistema (con el contexto ya aprobado) y el mensaje del ciudadano.
-- La clave se lee de Vault en el momento de la llamada
-- (vault.decrypted_secrets, nombre 'anthropic_api_key').

CREATE OR REPLACE FUNCTION public.generar_respuesta_claude(mensaje_sistema text, mensaje_usuario text, max_tokens integer DEFAULT 500)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'extensions', 'public', 'vault'
AS $function$
declare
  respuesta extensions.http_response;
  cuerpo jsonb;
begin
  select * into respuesta from extensions.http((
    'POST',
    'https://api.anthropic.com/v1/messages',
    ARRAY[
      extensions.http_header('x-api-key', (select decrypted_secret from vault.decrypted_secrets where name = 'anthropic_api_key')),
      extensions.http_header('anthropic-version', '2023-06-01')
    ],
    'application/json',
    jsonb_build_object(
      'model', 'claude-haiku-4-5-20251001',
      'max_tokens', max_tokens,
      'system', mensaje_sistema,
      'messages', jsonb_build_array(jsonb_build_object('role', 'user', 'content', mensaje_usuario))
    )::text
  )::extensions.http_request);

  if respuesta.status <> 200 then
    raise exception 'Error de Claude (status %): %', respuesta.status, respuesta.content;
  end if;

  cuerpo := respuesta.content::jsonb;
  return cuerpo -> 'content' -> 0 ->> 'text';
end;
$function$
;
