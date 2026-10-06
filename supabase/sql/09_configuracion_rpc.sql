-- Función para actualizar configuracion_agente desde la app de administración.
-- Valida los valores antes de guardarlos (umbral entre 0 y 1, horario de
-- inicio anterior al de fin, instrucciones no vacías) y exige estar
-- autenticado, además del permiso a nivel de grant.

create or replace function public.guardar_configuracion_agente(
  p_instrucciones_sistema text,
  p_umbral_confianza real,
  p_modelo_claude text,
  p_horario_inicio time,
  p_horario_fin time,
  p_frases_pedido_explicito text[],
  p_frases_disconformidad text[],
  p_mensaje_derivacion_horario text,
  p_mensaje_derivacion_fuera_horario text,
  p_actualizado_por text
)
returns public.configuracion_agente
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_resultado public.configuracion_agente;
begin
  if auth.uid() is null then
    raise exception 'No autenticado.';
  end if;

  if p_umbral_confianza is null or p_umbral_confianza <= 0 or p_umbral_confianza > 1 then
    raise exception 'El umbral de confianza debe ser un valor mayor a 0 y menor o igual a 1.';
  end if;

  if p_horario_inicio is null or p_horario_fin is null or p_horario_inicio >= p_horario_fin then
    raise exception 'El horario de inicio debe ser anterior al horario de fin.';
  end if;

  if coalesce(trim(p_instrucciones_sistema), '') = '' then
    raise exception 'Las instrucciones del sistema no pueden quedar vacías.';
  end if;

  if coalesce(trim(p_modelo_claude), '') = '' then
    raise exception 'El modelo de Claude no puede quedar vacío.';
  end if;

  update public.configuracion_agente
  set instrucciones_sistema = p_instrucciones_sistema,
      umbral_confianza = p_umbral_confianza,
      modelo_claude = p_modelo_claude,
      horario_inicio = p_horario_inicio,
      horario_fin = p_horario_fin,
      frases_pedido_explicito = coalesce(p_frases_pedido_explicito, '{}'),
      frases_disconformidad = coalesce(p_frases_disconformidad, '{}'),
      mensaje_derivacion_horario = p_mensaje_derivacion_horario,
      mensaje_derivacion_fuera_horario = p_mensaje_derivacion_fuera_horario,
      actualizado_por = p_actualizado_por,
      actualizado_en = now()
  where id = 1
  returning * into v_resultado;

  return v_resultado;
end;
$function$;

revoke all on function public.guardar_configuracion_agente from public;
grant execute on function public.guardar_configuracion_agente to authenticated;
