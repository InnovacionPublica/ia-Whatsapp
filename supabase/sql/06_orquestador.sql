-- Orquestador principal: decide qué hacer con cada mensaje entrante de un
-- ciudadano, en este orden de prioridad:
--   1. Si un operador humano tiene la conversación, la IA nunca responde.
--   2. Si ya estaba "pendiente" y seguimos fuera de horario, se lo informa.
--   3. Si ya estaba "pendiente" y volvió el horario, pasa a la cola humana.
--   4. Pedido explícito de hablar con una persona, o señales de
--      disconformidad -> se deriva (a "humano" si hay horario, o
--      "pendiente" si no).
--   5. Si no hay evidencia suficiente en la base de conocimiento (similitud
--      por debajo del umbral configurado) -> se deriva igual que el punto 4.
--   6. Si hay evidencia suficiente, se genera la respuesta con Claude,
--      usando ÚNICAMENTE fragmentos ya aprobados como contexto.
--
-- Desde el 6 de octubre de 2026, el umbral de confianza, el horario de
-- atención, las frases de derivación, los dos mensajes de derivación, las
-- instrucciones del sistema para Claude y el modelo usado se leen de
-- configuracion_agente (antes estaban hardcodeados acá), para que se
-- puedan editar desde la app de administración sin tocar código.
--
-- Los mensajes de "sigue pendiente" / "pendiente pasa a humano" (que no
-- forman parte de los parámetros editables pedidos) no mencionan un
-- horario fijo en el texto, para que no queden desactualizados si cambia
-- el horario configurado.

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
  v_embeddings vector[];
  v_embedding vector(1024);
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

  -- Buscar evidencia por significado entre lo ya aprobado.
  v_embeddings := generar_embeddings_voyage_lote(array[p_mensaje]);
  v_embedding := v_embeddings[1];

  select id, similitud into v_mejor_id, v_mejor_similitud
  from buscar_fragmentos_similares(v_embedding, 3)
  limit 1;

  if v_mejor_id is null or v_mejor_similitud < v_config.umbral_confianza then
    v_motivo := 'No se encontró evidencia suficiente (similitud=' ||
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
  select string_agg('- ' || contenido, E'

' order by similitud desc)
  into v_contexto
  from buscar_fragmentos_similares(v_embedding, 3);

  v_sistema := v_config.instrucciones_sistema || E'

Contexto:
' || v_contexto;

  v_respuesta := generar_respuesta_claude(v_sistema, p_mensaje, 500, v_config.modelo_claude);

  insert into interacciones (ciudadano_id, mensaje, accion, respuesta, fragmento_usado_id, score, motivo, estado_resultante)
  values (p_ciudadano_id, p_mensaje, 'respondido_ia', v_respuesta, v_mejor_id, v_mejor_similitud,
          'Evidencia suficiente encontrada (similitud=' || round(v_mejor_similitud::numeric, 2) || ').', 'ia');

  return jsonb_build_object('accion', 'respondido_ia', 'respuesta', v_respuesta, 'estado_resultante', 'ia');
end;
$function$
;
