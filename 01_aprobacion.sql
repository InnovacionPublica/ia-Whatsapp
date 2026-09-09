-- Funciones de aprobación de contenido (Etapa 14).
-- Las usa tanto el backend como el panel web (Etapa 18), ahora que el panel
-- también puede llamarlas desde una sesión de usuario autenticado.

CREATE OR REPLACE FUNCTION public.aprobar_fragmentos(ids uuid[], aprobado_por text)
 RETURNS integer
 LANGUAGE sql
 SECURITY DEFINER
AS $function$
  with actualizados as (
    update fragmentos_conocimiento
    set estado = 'activo', aprobado_por = aprobar_fragmentos.aprobado_por, fecha_actualizacion = now()
    where id = any(ids) and estado = 'en_revision'
    returning id
  )
  select count(*)::integer from actualizados;
$function$
;

CREATE OR REPLACE FUNCTION public.aprobar_fragmentos_de_documento(documento_id uuid, aprobado_por text)
 RETURNS integer
 LANGUAGE sql
 SECURITY DEFINER
AS $function$
  with actualizados as (
    update fragmentos_conocimiento
    set estado = 'activo', aprobado_por = aprobar_fragmentos_de_documento.aprobado_por, fecha_actualizacion = now()
    where documento_fuente_id = documento_id and estado = 'en_revision'
    returning id
  )
  select count(*)::integer from actualizados;
$function$
;

CREATE OR REPLACE FUNCTION public.aprobar_todo_lo_pendiente(aprobado_por text)
 RETURNS integer
 LANGUAGE sql
 SECURITY DEFINER
AS $function$
  with actualizados as (
    update fragmentos_conocimiento
    set estado = 'activo', aprobado_por = aprobar_todo_lo_pendiente.aprobado_por, fecha_actualizacion = now()
    where estado = 'en_revision'
    returning id
  )
  select count(*)::integer from actualizados;
$function$
;

CREATE OR REPLACE FUNCTION public.listar_fragmentos_pendientes()
 RETURNS TABLE(id uuid, tema text, contenido text, fuente text, fecha_actualizacion timestamp with time zone)
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select id, tema, contenido, fuente, fecha_actualizacion
  from fragmentos_conocimiento
  where estado = 'en_revision'
  order by fecha_actualizacion asc;
$function$
;
