-- Guardado de credenciales de Meta/WhatsApp (token, phone_number_id,
-- verify_token) directo a Supabase Vault desde la app de administración.
-- El valor de la credencial nunca se devuelve ni se guarda en ninguna
-- tabla en texto plano -- solo vive cifrado en Vault. Para trazabilidad
-- se registra en auditoria_credenciales quién cambió cuál credencial y
-- cuándo (nunca el valor).

create table public.auditoria_credenciales (
  id bigint generated always as identity primary key,
  nombre text not null,
  actualizado_por text,
  actualizado_en timestamptz not null default now()
);

comment on table public.auditoria_credenciales is
  'Registro de trazabilidad: quién actualizó cada credencial de Meta/WhatsApp y cuándo. Nunca guarda el valor de la credencial.';

alter table public.auditoria_credenciales enable row level security;

create policy "lectura_auditoria_autenticados"
  on public.auditoria_credenciales for select
  to authenticated
  using (true);

create or replace function public.guardar_credencial_meta(p_nombre text, p_valor text, p_actualizado_por text)
returns boolean
language plpgsql
security definer
set search_path to 'public', 'vault'
as $function$
declare
  v_id uuid;
  v_nombres_permitidos constant text[] := array['meta_whatsapp_token', 'meta_phone_number_id', 'meta_verify_token'];
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

revoke all on function public.guardar_credencial_meta from public;
grant execute on function public.guardar_credencial_meta to authenticated;

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
  from unnest(array['meta_whatsapp_token', 'meta_phone_number_id', 'meta_verify_token']) as nombres(nombre)
  left join vault.secrets s on s.name = nombres.nombre;
end;
$function$;

revoke all on function public.estado_credenciales_meta from public;
grant execute on function public.estado_credenciales_meta to authenticated;
