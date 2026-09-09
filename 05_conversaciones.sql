-- Funciones de gestión manual del estado de una conversación, para cuando
-- un operador humano interviene o termina de atender.

CREATE OR REPLACE FUNCTION public.liberar_conversacion_a_ia(p_ciudadano_id text)
 RETURNS void
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  update conversaciones set estado = 'ia', actualizado_en = now() where ciudadano_id = p_ciudadano_id;
$function$
;

CREATE OR REPLACE FUNCTION public.operador_responde(p_ciudadano_id text, p_texto text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  insert into conversaciones (ciudadano_id, estado)
  values (p_ciudadano_id, 'humano')
  on conflict (ciudadano_id) do update set estado = 'humano', actualizado_en = now();

  insert into interacciones (ciudadano_id, mensaje, accion, respuesta, motivo, estado_resultante)
  values (p_ciudadano_id, '(respuesta de operador)', 'respuesta_humana', p_texto,
          'Un operador respondió manualmente.', 'humano');
end;
$function$
;
