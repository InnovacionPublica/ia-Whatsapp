-- Tabla de configuración del agente: una sola fila con los parámetros que
-- hoy están hardcodeados en procesar_mensaje_ciudadano y generar_respuesta_claude.
-- La idea es que la futura app de administración (Vercel) lea y actualice
-- esta fila en vez de que haya que tocar código SQL para cambiar un parámetro.
--
-- Solo se puede LEER directamente (rol authenticated, es decir ya logueado
-- en el panel). No hay política de escritura: toda actualización pasa por
-- una función RPC (guardar_configuracion_agente, en 09_configuracion_rpc.sql)
-- para poder validar los valores y dejar registro de quién cambió qué.

create table public.configuracion_agente (
  id integer primary key default 1,
  instrucciones_sistema text not null,
  umbral_confianza real not null default 0.50,
  modelo_claude text not null default 'claude-haiku-4-5-20251001',
  horario_inicio time not null default '06:00',
  horario_fin time not null default '14:00',
  frases_pedido_explicito text[] not null default array[
    'hablar con una persona','hablar con alguien','quiero un operador',
    'atencion humana','necesito un humano','pasame con alguien',
    'quiero hablar con un empleado','atencion personal'
  ],
  frases_disconformidad text[] not null default array[
    'no me sirve','no es lo que pregunte','no entendiste','sigo sin entender',
    'eso ya lo probe','no funciona','no resolviste','necesito otra solucion',
    'esto no me ayuda','segui con el mismo problema','ya te dije que'
  ],
  mensaje_derivacion_horario text not null default
    'Te voy a poner en contacto con una persona del equipo para que te ayude con esto. En un momento te responden por este mismo chat.',
  mensaje_derivacion_fuera_horario text not null default
    'En este momento no hay operadores disponibles (atendemos de 6 a 14 hs). Tu consulta quedó registrada y va a ser retomada apenas comience el horario de atención. No puedo garantizarte un horario exacto de respuesta.',
  actualizado_por text,
  actualizado_en timestamptz not null default now(),
  constraint configuracion_agente_fila_unica check (id = 1)
);

comment on table public.configuracion_agente is
  'Fila única con los parámetros editables del agente desde la app de administración: instrucciones del sistema para Claude, umbral de confianza, modelo, horario de atención y frases/mensajes de derivación a un humano.';

alter table public.configuracion_agente enable row level security;

create policy "lectura_configuracion_autenticados"
  on public.configuracion_agente for select
  to authenticated
  using (true);

insert into public.configuracion_agente (id, instrucciones_sistema)
values (1,
  'Sos el asistente de atención ciudadana de la Secretaría de Gestión Pública de Santa Fe, en WhatsApp. ' ||
  'Respondé la consulta del ciudadano ÚNICAMENTE con la información del siguiente contexto, ya aprobado por el equipo. ' ||
  'No agregues datos que no estén en el contexto, no completes con conocimiento general ni supongas nada. ' ||
  'Si el contexto no alcanza para responder con seguridad, decilo explícitamente en vez de inventar. ' ||
  'Usá un tono claro, cordial e institucional, sin markdown ni emojis (esto se envía como mensaje de WhatsApp).'
);
