-- Refuerzo del webhook de WhatsApp (14 de octubre de 2026):
--   1) Nueva credencial "meta_app_secret" (clave secreta de la app de Meta), que
--      se guarda en Vault igual que las otras. Sirve para comprobar la firma
--      (X-Hub-Signature-256) de cada mensaje que Meta envía al webhook.
--   2) Registro de mensajes ya procesados, para que un reintento de Meta no
--      genere una respuesta duplicada (Meta entrega "al menos una vez").
-- Las dos funciones nuevas solo las puede ejecutar la función de borde
-- (service_role); nunca anon ni authenticated.

create or replace function public.guardar_credencial_meta(p_nombre text, p_valor text, p_actualizado_por text)
returns boolean
language plpgsql
security definer
set search_path to 'public', 'vault'
as $function$
declare
  v_id uuid;
  v_nombres_permitidos constant text[] := array['meta_whatsapp_token', 'meta_phone_number_id', 'meta_verify_token', 'meta_app_secret'];
begin
  if auth.uid() is null then
    raise exception 'No autenticado.';
  end if;

  if not (p_nombre = any(v_nombres_permitidos)) then
    raise exception 'Nombre de credencial no reconocido: %', p_nombre;
  end if;

  if coalesce(trim(p_valor), '') = '' then
    raise exception 'El valor de la credencial no puede estar vacío.';
  end if;

  select id into v_id from vault.secrets where name = p_nombre;

  if v_id is null then
    perform vault.create_secret(p_valor, p_nombre);
  else
    perform vault.update_secret(v_id, p_valor);
  end if;

  insert into public.auditoria_credenciales (nombre, actualizado_por)
  values (p_nombre, p_actualizado_por);

  return true;
end;
$function$;

create or replace function public.estado_credenciales_meta()
returns table(nombre text, cargada boolean)
language plpgsql
security definer
set search_path to 'public', 'vault'
as $function$
begin
  if auth.uid() is null then
    raise exception 'No autenticado.';
  end if;

  return query
  select nombres.nombre, (s.name is not null) as cargada
  from unnest(array['meta_whatsapp_token', 'meta_phone_number_id', 'meta_verify_token', 'meta_app_secret']) as nombres(nombre)
  left join vault.secrets s on s.name = nombres.nombre;
end;
$function$;

create table if not exists public.mensajes_procesados (
  id text primary key,
  recibido_en timestamptz not null default now()
);

comment on table public.mensajes_procesados is
  'Ids de mensajes de WhatsApp ya procesados (anti-duplicados). No contiene el texto ni el teléfono.';

alter table public.mensajes_procesados enable row level security;
-- Sin políticas y sin permisos de tabla: solo accede service_role a través de las funciones de abajo.
revoke all on table public.mensajes_procesados from anon, authenticated;

create or replace function public.registrar_mensaje_entrante(p_id text)
returns boolean
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_filas integer;
begin
  insert into public.mensajes_procesados (id) values (p_id) on conflict (id) do nothing;
  get diagnostics v_filas = row_count;
  return v_filas = 1; -- true: mensaje nuevo; false: ya procesado antes
end;
$function$;

create or replace function public.obtener_app_secret_whatsapp()
returns text
language sql
security definer
stable
set search_path to 'public', 'vault'
as $function$
  select decrypted_secret from vault.decrypted_secrets where name = 'meta_app_secret' limit 1;
$function$;

revoke all on function public.registrar_mensaje_entrante(text) from public, anon, authenticated;
revoke all on function public.obtener_app_secret_whatsapp() from public, anon, authenticated;
grant execute on function public.registrar_mensaje_entrante(text) to service_role;
grant execute on function public.obtener_app_secret_whatsapp() to service_role;
