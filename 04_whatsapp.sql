-- Envío de mensajes por WhatsApp (Meta Cloud API directa, Etapa 17) y
-- verificación del token del webhook. Las credenciales se leen de Vault
-- (meta_whatsapp_token, meta_phone_number_id, meta_verify_token).

CREATE OR REPLACE FUNCTION public.enviar_mensaje_whatsapp(destino text, texto text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'extensions', 'public', 'vault'
AS $function$
declare
  v_token text;
  v_phone_number_id text;
  respuesta extensions.http_response;
begin
  select decrypted_secret into v_token from vault.decrypted_secrets where name = 'meta_whatsapp_token';
  select decrypted_secret into v_phone_number_id from vault.decrypted_secrets where name = 'meta_phone_number_id';

  if v_token is null or v_phone_number_id is null then
    raise exception 'Faltan las credenciales de Meta en Vault (meta_whatsapp_token / meta_phone_number_id).';
  end if;

  select * into respuesta from extensions.http((
    'POST',
    'https://graph.facebook.com/v21.0/' || v_phone_number_id || '/messages',
    ARRAY[extensions.http_header('Authorization', 'Bearer ' || v_token)],
    'application/json',
    jsonb_build_object(
      'messaging_product', 'whatsapp',
      'to', destino,
      'type', 'text',
      'text', jsonb_build_object('body', texto)
    )::text
  )::extensions.http_request);

  if respuesta.status not between 200 and 299 then
    raise exception 'Error al enviar por WhatsApp (status %): %', respuesta.status, respuesta.content;
  end if;

  return respuesta.content::jsonb;
end;
$function$
;

CREATE OR REPLACE FUNCTION public.verificar_token_whatsapp(token_recibido text)
 RETURNS boolean
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'vault'
AS $function$
  select exists (
    select 1 from vault.decrypted_secrets
    where name = 'meta_verify_token' and decrypted_secret = token_recibido
  );
$function$
;
