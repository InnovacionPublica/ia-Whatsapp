-- Orquestador principal: procesa cada mensaje entrante de un ciudadano y
-- decide qué hacer, siguiendo siempre el mismo orden de prioridad:
--
--   1. Si un operador humano ya tiene la conversación, la IA nunca responde.
--   2. Si la conversación quedó "pendiente" (derivada fuera de horario) y
--      seguimos fuera de horario, se avisa que sigue en espera.
--   3. Si estaba "pendiente" y ya volvió el horario de atención (6-14 hs),
--      pasa a la cola de un operador (sin que la IA conteste ese mensaje).
--   4. Si el ciudadano pide explícitamente hablar con una persona, o se
--      detectan señales de disconformidad con una respuesta anterior, se
--      deriva (a un operador si hay horario, o a "pendiente" si no).
--   5. Si no hay evidencia suficiente en la base de conocimiento aprobada
--      (similitud por debajo del umbral), también se deriva.
--   6. Solo si hay evidencia suficiente, se genera una respuesta con Claude,
--      usando ÚNICAMENTE fragmentos con estado = 'activo' como contexto.
--
-- Esta es la regla más importante del proyecto: el sistema nunca responde
-- con información que no haya sido cargada y aprobada antes por el equipo.

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
  v_umbral_confianza constant float := 0.50;
  v_mensaje_derivacion_horario constant text :=
    'Te voy a poner en contacto con una persona del equipo para que te ayude con esto. En un momento te responden por este mismo chat.';
  v_mensaje_derivacion_fuera_horario constant text :=
    'En este momento no hay operadores disponibles (atendemos de 6 a 14 hs). Tu consulta quedó registrada y va a ser retomada apenas comience el horario de atención. No puedo garantizarte un horario exacto de respuesta.';
begin
  insert into conversaciones (ciudadano_id, estado)
  values (p_ciudadano_id, 'ia')
  on conflict (ciudadano_id) do nothing;

  select estado into v_estado from conversaciones where ciudadano_id = p_ciudadano_id;

  v_hora_local := (p_ahora at time zone 'America/Argentina/Buenos_Aires')::time;
  v_en_horario := v_hora_local >= time '06:00' and v_hora_local < time '14:00';

  -- Un operador tiene el control: la IA nunca interviene.
  if v_estado = 'humano' then
    insert into interacciones (ciudadano_id, mensaje, accion, respuesta, motivo, estado_resultante)
    values (p_ciudadano_id, p_mensaje, 'ia_bloqueada', null,
            'La conversación está bajo control de un operador humano; la IA no responde.', v_estado);
    return jsonb_build_object('accion', 'ia_bloqueada', 'respuesta', null, 'estado_resultante', v_estado);
  end if;

  -- Sigue pendiente y seguimos fuera de horario.
  if v_estado = 'pendiente' and not v_en_horario then
    v_respuesta := 'Tu consulta anterior quedó registrada para ser atendida por una persona en el horario de atención (6 a 14 hs). Todavía estamos fuera de ese horario.';
    insert into interacciones (ciudadano_id, mensaje, accion, respuesta, motivo, estado_resultante)
    values (p_ciudadano_id, p_mensaje, 'sigue_pendiente', v_respuesta,
            'Ya estaba en cola de pendientes y seguimos fuera de horario.', v_estado);
    return jsonb_build_object('accion', 'sigue_pendiente', 'respuesta', v_respuesta, 'estado_resultante', v_estado);
  end if;

  -- Estaba pendiente y ya volvió el horario humano: pasa a "humano", sin
  -- que la IA responda en el mismo mensaje.
  if v_estado = 'pendiente' and v_en_horario then
    update conversaciones set estado = 'humano', actualizado_en = now() where ciudadano_id = p_ciudadano_id;
    v_respuesta := 'Ya volvió el horario de atención (6 a 14 hs): un operador va a retomar tu consulta pendiente en breve.';
    insert into interacciones (ciudadano_id, mensaje, accion, respuesta, motivo, estado_resultante)
    values (p_ciudadano_id, p_mensaje, 'pendiente_pasa_a_humano', v_respuesta,
            'Volvió el horario de atención; la consulta pendiente pasa a la cola de un operador.', 'humano');
    return jsonb_build_object('accion', 'pendiente_pasa_a_humano', 'respuesta', v_respuesta, 'estado_resultante', 'humano');
  end if;

  -- A partir de acá, v_estado = 'ia'.
  v_texto_normalizado := lower(extensions.unaccent(p_mensaje));

  if exists (
    select 1 from unnest(array[
      'hablar con una persona', 'hablar con alguien', 'quiero un operador',
      'atencion humana', 'necesito un humano', 'pasame con alguien',
      'quiero hablar con un empleado', 'atencion personal'
    ]) f where v_texto_normalizado like '%' || f || '%'
  ) then
    v_accion := 'derivar_pedido_explicito';
    v_motivo := 'El ciudadano pidió explícitamente hablar con una persona.';
  elsif exists (
    select 1 from unnest(array[
      'no me sirve', 'no es lo que pregunte', 'no entendiste', 'sigo sin entender',
      'eso ya lo probe', 'no funciona', 'no resolviste', 'necesito otra solucion',
      'esto no me ayuda', 'segui con el mismo problema', 'ya te dije que'
    ]) f where v_texto_normalizado like '%' || f || '%'
  ) then
    v_accion := 'derivar_disconformidad';
    v_motivo := 'Se detectaron señales de disconformidad con una respuesta anterior.';
  end if;

  if v_accion is not null then
    if v_en_horario then
      update conversaciones set estado = 'humano', actualizado_en = now() where ciudadano_id = p_ciudadano_id;
      v_estado_resultante := 'humano';
      v_respuesta := v_mensaje_derivacion_horario;
    else
      update conversaciones set estado = 'pendiente', actualizado_en = now() where ciudadano_id = p_ciudadano_id;
      v_estado_resultante := 'pendiente';
      v_respuesta := v_mensaje_derivacion_fuera_horario;
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

  if v_mejor_id is null or v_mejor_similitud < v_umbral_confianza then
    v_motivo := 'No se encontró evidencia suficiente (similitud=' ||
                coalesce(round(v_mejor_similitud::numeric, 2)::text, '0') || ' < umbral ' || v_umbral_confianza || ').';
    if v_en_horario then
      update conversaciones set estado = 'humano', actualizado_en = now() where ciudadano_id = p_ciudadano_id;
      v_estado_resultante := 'humano';
      v_respuesta := v_mensaje_derivacion_horario;
    else
      update conversaciones set estado = 'pendiente', actualizado_en = now() where ciudadano_id = p_ciudadano_id;
      v_estado_resultante := 'pendiente';
      v_respuesta := v_mensaje_derivacion_fuera_horario;
    end if;

    insert into interacciones (ciudadano_id, mensaje, accion, respuesta, fragmento_usado_id, score, motivo, estado_resultante)
    values (p_ciudadano_id, p_mensaje, 'derivar_sin_evidencia', v_respuesta, v_mejor_id, v_mejor_similitud, v_motivo, v_estado_resultante);

    return jsonb_build_object('accion', 'derivar_sin_evidencia', 'respuesta', v_respuesta, 'estado_resultante', v_estado_resultante);
  end if;

  -- Hay evidencia suficiente: se genera la respuesta con Claude, usando
  -- ÚNICAMENTE contenido ya aprobado (estado = 'activo') como contexto.
  select string_agg('- ' || contenido, E'\n\n' order by similitud desc)
  into v_contexto
  from buscar_fragmentos_similares(v_embedding, 3);

  v_sistema := 'Sos el asistente de atención ciudadana de la Secretaría de Gestión Pública de Santa Fe, en WhatsApp. '
    || 'Respondé la consulta del ciudadano ÚNICAMENTE con la información del siguiente contexto, ya aprobado por el equipo. '
    || 'No agregues datos que no estén en el contexto, no completes con conocimiento general ni supongas nada. '
    || 'Si el contexto no alcanza para responder con seguridad, decilo explícitamente en vez de inventar. '
    || 'Usá un tono claro, cordial e institucional, sin markdown ni emojis (esto se envía como mensaje de WhatsApp).'
    || E'\n\nContexto:\n' || v_contexto;

  v_respuesta := generar_respuesta_claude(v_sistema, p_mensaje);

  insert into interacciones (ciudadano_id, mensaje, accion, respuesta, fragmento_usado_id, score, motivo, estado_resultante)
  values (p_ciudadano_id, p_mensaje, 'respondido_ia', v_respuesta, v_mejor_id, v_mejor_similitud,
          'Evidencia suficiente encontrada (similitud=' || round(v_mejor_similitud::numeric, 2) || ').', 'ia');

  return jsonb_build_object('accion', 'respondido_ia', 'respuesta', v_respuesta, 'estado_resultante', 'ia');
end;
$function$
;
