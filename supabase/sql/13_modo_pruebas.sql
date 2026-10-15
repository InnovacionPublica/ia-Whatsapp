-- Modo pruebas con palabra de activación (14 de octubre de 2026).
--
-- Con el modo pruebas encendido, el agente NO responde a nadie hasta que esa
-- persona escribe la palabra de activación (por defecto "#prueba"). Desde ahí
-- la conversación queda activa durante N horas (por defecto 24) o hasta que
-- escriba la palabra de salida (por defecto "#salir"). A quien escribe sin
-- haber activado no se le responde y NO se guarda el contenido de su mensaje
-- (solo queda el identificador técnico anti-duplicados).
-- Para abrir el servicio al público basta con apagar el modo pruebas desde
-- el panel (pestaña IA).

alter table public.configuracion_agente
  add column if not exists modo_pruebas boolean not null default true,
  add column if not exists palabra_activacion text not null default '#prueba',
  add column if not exists palabra_salida text not null default '#salir',
  add column if not exists horas_activacion integer not null default 24;

create table if not exists public.activaciones_prueba (
  ciudadano_id text primary key,
  activada_en timestamptz not null default now()
);
alter table public.activaciones_prueba enable row level security;
revoke all on table public.activaciones_prueba from public, anon, authenticated;

-- Orquestador con la compuerta del modo pruebas al principio.
CREATE OR REPLACE FUNCTION public.procesar_mensaje_ciudadano(p_ciudadano_id text, p_mensaje text, p_ahora timestamp with time zone DEFAULT now())
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions', 'vault'
AS $function$
declare
  v_estado text;
  v_hora_local time;
  v_en_horario boolean;
  v_texto_normalizado text;
  v_texto_gate text;
  v_activa boolean;
  v_mejor_id uuid;
  v_mejor_similitud float;
  v_contexto text;
  v_sistema text;
  v_respuesta text;
  v_accion text;
  v_motivo text;
  v_estado_resultante text;
  v_config public.configuracion_agente;
begin
  select * into v_config from public.configuracion_agente where id = 1;
  if v_config is null then
    raise exception 'No hay configuración del agente cargada (tabla configuracion_agente vacía).';
  end if;

  -- Compuerta del modo pruebas: sin activación no se responde ni se guarda nada.
  if v_config.modo_pruebas then
    v_texto_gate := btrim(lower(extensions.unaccent(p_mensaje)), E' \t\r\n.!?¡¿');

    select (activada_en > p_ahora - make_interval(hours => v_config.horas_activacion))
      into v_activa
    from public.activaciones_prueba where ciudadano_id = p_ciudadano_id;
    v_activa := coalesce(v_activa, false);

    if v_texto_gate = btrim(lower(extensions.unaccent(v_config.palabra_activacion)), E' \t\r\n.!?¡¿') then
      insert into public.activaciones_prueba (ciudadano_id, activada_en)
      values (p_ciudadano_id, p_ahora)
      on conflict (ciudadano_id) do update set activada_en = excluded.activada_en;

      insert into conversaciones (ciudadano_id, estado)
      values (p_ciudadano_id, 'ia')
      on conflict (ciudadano_id) do update set estado = 'ia', actualizado_en = now();

      v_respuesta := 'Modo prueba activado por ' || v_config.horas_activacion ||
                     ' horas. Ya podés hacer tu consulta. Para terminar, escribí ' || v_config.palabra_salida || '.';
      insert into interacciones (ciudadano_id, mensaje, accion, respuesta, motivo, estado_resultante)
      values (p_ciudadano_id, p_mensaje, 'activacion_prueba', v_respuesta,
              'La persona escribió la palabra de activación del modo pruebas.', 'ia');
      return jsonb_build_object('accion', 'activacion_prueba', 'respuesta', v_respuesta, 'estado_resultante', 'ia');
    elsif v_activa and v_texto_gate = btrim(lower(extensions.unaccent(v_config.palabra_salida)), E' \t\r\n.!?¡¿') then
      delete from public.activaciones_prueba where ciudadano_id = p_ciudadano_id;
      v_respuesta := 'Modo prueba finalizado. Para volver a activarlo, escribí ' || v_config.palabra_activacion || '.';
      insert into interacciones (ciudadano_id, mensaje, accion, respuesta, motivo, estado_resultante)
      values (p_ciudadano_id, p_mensaje, 'salida_prueba', v_respuesta,
              'La persona escribió la palabra de salida del modo pruebas.', 'ia');
      return jsonb_build_object('accion', 'salida_prueba', 'respuesta', v_respuesta, 'estado_resultante', 'ia');
    elsif not v_activa then
      return jsonb_build_object('accion', 'ignorado_modo_pruebas', 'respuesta', null, 'estado_resultante', null);
    end if;
  end if;

  insert into conversaciones (ciudadano_id, estado)
  values (p_ciudadano_id, 'ia')
  on conflict (ciudadano_id) do nothing;

  select estado into v_estado from conversaciones where ciudadano_id = p_ciudadano_id;

  v_hora_local := (p_ahora at time zone 'America/Argentina/Buenos_Aires')::time;
  v_en_horario := v_hora_local >= v_config.horario_inicio and v_hora_local < v_config.horario_fin;

  -- Un operador tiene el control: la IA nunca interviene.
  if v_estado = 'humano' then
    insert into interacciones (ciudadano_id, mensaje, accion, respuesta, motivo, estado_resultante)
    values (p_ciudadano_id, p_mensaje, 'ia_bloqueada', null,
            'La conversación está bajo control de un operador humano; la IA no responde.', v_estado);
    return jsonb_build_object('accion', 'ia_bloqueada', 'respuesta', null, 'estado_resultante', v_estado);
  end if;

  -- Sigue pendiente y seguimos fuera de horario.
  if v_estado = 'pendiente' and not v_en_horario then
    v_respuesta := 'Tu consulta anterior quedó registrada para ser atendida por una persona en el horario de atención. Todavía estamos fuera de ese horario.';
    insert into interacciones (ciudadano_id, mensaje, accion, respuesta, motivo, estado_resultante)
    values (p_ciudadano_id, p_mensaje, 'sigue_pendiente', v_respuesta,
            'Ya estaba en cola de pendientes y seguimos fuera de horario.', v_estado);
    return jsonb_build_object('accion', 'sigue_pendiente', 'respuesta', v_respuesta, 'estado_resultante', v_estado);
  end if;

  -- Estaba pendiente y ya volvió el horario humano: pasa a "humano", sin
  -- que la IA responda en el mismo mensaje.
  if v_estado = 'pendiente' and v_en_horario then
    update conversaciones set estado = 'humano', actualizado_en = now() where ciudadano_id = p_ciudadano_id;
    v_respuesta := 'Ya volvió el horario de atención: un operador va a retomar tu consulta pendiente en breve.';
    insert into interacciones (ciudadano_id, mensaje, accion, respuesta, motivo, estado_resultante)
    values (p_ciudadano_id, p_mensaje, 'pendiente_pasa_a_humano', v_respuesta,
            'Volvió el horario de atención; la consulta pendiente pasa a la cola de un operador.', 'humano');
    return jsonb_build_object('accion', 'pendiente_pasa_a_humano', 'respuesta', v_respuesta, 'estado_resultante', 'humano');
  end if;

  -- A partir de acá, v_estado = 'ia'.
  v_texto_normalizado := lower(extensions.unaccent(p_mensaje));

  if exists (
    select 1 from unnest(v_config.frases_pedido_explicito) f where v_texto_normalizado like '%' || f || '%'
  ) then
    v_accion := 'derivar_pedido_explicito';
    v_motivo := 'El ciudadano pidió explícitamente hablar con una persona.';
  elsif exists (
    select 1 from unnest(v_config.frases_disconformidad) f where v_texto_normalizado like '%' || f || '%'
  ) then
    v_accion := 'derivar_disconformidad';
    v_motivo := 'Se detectaron señales de disconformidad con una respuesta anterior.';
  end if;

  if v_accion is not null then
    if v_en_horario then
      update conversaciones set estado = 'humano', actualizado_en = now() where ciudadano_id = p_ciudadano_id;
      v_estado_resultante := 'humano';
      v_respuesta := v_config.mensaje_derivacion_horario;
    else
      update conversaciones set estado = 'pendiente', actualizado_en = now() where ciudadano_id = p_ciudadano_id;
      v_estado_resultante := 'pendiente';
      v_respuesta := v_config.mensaje_derivacion_fuera_horario;
    end if;

    insert into interacciones (ciudadano_id, mensaje, accion, respuesta, motivo, estado_resultante)
    values (p_ciudadano_id, p_mensaje, v_accion, v_respuesta, v_motivo, v_estado_resultante);

    return jsonb_build_object('accion', v_accion, 'respuesta', v_respuesta, 'estado_resultante', v_estado_resultante);
  end if;

  -- Buscar evidencia por texto entre lo ya aprobado (búsqueda por palabras en español).
  select id, similitud into v_mejor_id, v_mejor_similitud
  from buscar_fragmentos_texto(p_mensaje, 3)
  limit 1;

  if v_mejor_id is null or v_mejor_similitud < v_config.umbral_confianza then
    v_motivo := 'No se encontró evidencia suficiente (puntaje=' ||
                coalesce(round(v_mejor_similitud::numeric, 2)::text, '0') || ' < umbral ' || v_config.umbral_confianza || ').';
    if v_en_horario then
      update conversaciones set estado = 'humano', actualizado_en = now() where ciudadano_id = p_ciudadano_id;
      v_estado_resultante := 'humano';
      v_respuesta := v_config.mensaje_derivacion_horario;
    else
      update conversaciones set estado = 'pendiente', actualizado_en = now() where ciudadano_id = p_ciudadano_id;
      v_estado_resultante := 'pendiente';
      v_respuesta := v_config.mensaje_derivacion_fuera_horario;
    end if;

    insert into interacciones (ciudadano_id, mensaje, accion, respuesta, fragmento_usado_id, score, motivo, estado_resultante)
    values (p_ciudadano_id, p_mensaje, 'derivar_sin_evidencia', v_respuesta, v_mejor_id, v_mejor_similitud, v_motivo, v_estado_resultante);

    return jsonb_build_object('accion', 'derivar_sin_evidencia', 'respuesta', v_respuesta, 'estado_resultante', v_estado_resultante);
  end if;

  -- Hay evidencia suficiente: se genera la respuesta con Claude, usando
  -- ÚNICAMENTE contenido ya aprobado (estado = 'activo') como contexto.
  select string_agg('- ' || contenido, E'\n\n' order by similitud desc)
  into v_contexto
  from buscar_fragmentos_texto(p_mensaje, 3);

  v_sistema := v_config.instrucciones_sistema || E'\n\nContexto:\n' || v_contexto;

  v_respuesta := generar_respuesta_claude(v_sistema, p_mensaje, 500, v_config.modelo_claude);

  insert into interacciones (ciudadano_id, mensaje, accion, respuesta, fragmento_usado_id, score, motivo, estado_resultante)
  values (p_ciudadano_id, p_mensaje, 'respondido_ia', v_respuesta, v_mejor_id, v_mejor_similitud,
          'Evidencia suficiente encontrada (puntaje=' || round(v_mejor_similitud::numeric, 2) || ').', 'ia');

  return jsonb_build_object('accion', 'respondido_ia', 'respuesta', v_respuesta, 'estado_resultante', 'ia');
end;
$function$;

-- Función del panel para guardar solo los parámetros del modo pruebas
-- (la función guardar_configuracion_agente queda como estaba).
create or replace function public.guardar_modo_pruebas(
  p_modo_pruebas boolean,
  p_palabra_activacion text,
  p_palabra_salida text,
  p_horas_activacion integer,
  p_actualizado_por text
)
returns public.configuracion_agente
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_resultado public.configuracion_agente;
  v_activacion text := trim(coalesce(p_palabra_activacion, ''));
  v_salida text := trim(coalesce(p_palabra_salida, ''));
begin
  if auth.uid() is null then
    raise exception 'No autenticado.';
  end if;
  if p_modo_pruebas is null then
    raise exception 'Indicá si el modo pruebas está activado o no.';
  end if;
  if v_activacion = '' or v_salida = '' then
    raise exception 'La palabra de activación y la de salida no pueden quedar vacías.';
  end if;
  if lower(v_activacion) = lower(v_salida) then
    raise exception 'La palabra de activación y la de salida tienen que ser distintas.';
  end if;
  if p_horas_activacion is null or p_horas_activacion < 1 or p_horas_activacion > 168 then
    raise exception 'La duración de la activación tiene que estar entre 1 y 168 horas.';
  end if;

  update public.configuracion_agente
  set modo_pruebas = p_modo_pruebas,
      palabra_activacion = v_activacion,
      palabra_salida = v_salida,
      horas_activacion = p_horas_activacion,
      actualizado_por = p_actualizado_por,
      actualizado_en = now()
  where id = 1
  returning * into v_resultado;

  return v_resultado;
end;
$function$;

revoke all on function public.guardar_modo_pruebas(boolean, text, text, integer, text) from public, anon;
grant execute on function public.guardar_modo_pruebas(boolean, text, text, integer, text) to authenticated;
