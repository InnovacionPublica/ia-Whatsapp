-- Hardening de permisos (6 de octubre de 2026).
--
-- Al revisar los permisos de ejecución de las funciones sensibles antes de
-- sumar las nuevas (configuración del agente + credenciales de WhatsApp),
-- se encontró que varias funciones quedaron ejecutables con la clave
-- pública (anon) -- la misma clave "publishable" que está a propósito en
-- panel/index.html, y por lo tanto visible para cualquiera que abra el
-- repositorio de GitHub (es público) o el código fuente del panel.
--
-- Ninguna de esas funciones necesita ese permiso:
--   - el webhook de WhatsApp (Edge Function) llama siempre con la
--     service_role key, que no depende de estos permisos;
--   - el panel las llama ya autenticado (rol "authenticated", después del
--     login), nunca como anon.
--
-- Es decir: estaban accesibles sin pasar por el login, cosa que no era
-- necesaria para que nada funcionara. Se revoca el permiso de anon en las
-- ocho funciones afectadas. No cambia nada para el webhook ni para el panel.

revoke execute on function public.buscar_fragmentos_similares(vector, integer) from anon;
revoke execute on function public.enviar_mensaje_whatsapp(text, text) from anon;
revoke execute on function public.generar_respuesta_claude(text, text, integer) from anon;
revoke execute on function public.liberar_conversacion_a_ia(text) from anon;
revoke execute on function public.listar_fragmentos_pendientes() from anon;
revoke execute on function public.operador_responde(text, text) from anon;
revoke execute on function public.procesar_mensaje_ciudadano(text, text, timestamptz) from anon;
revoke execute on function public.verificar_token_whatsapp(text) from anon;

-- Nota (misma fecha, al sumar las funciones de configuracion_agente):
-- este proyecto tiene como default que toda función nueva en "public"
-- otorga EXECUTE a anon y authenticated automáticamente. Se corrigió de
-- raíz para que no vuelva a pasar con las funciones que se creen de ahora
-- en más:
alter default privileges for role postgres in schema public
  revoke execute on functions from anon;

-- Dos funciones puntuales (disparar_procesamiento_documento, y una nueva
-- sobrecarga de generar_respuesta_claude con el modelo configurable)
-- además tenían un grant a PUBLIC -- que incluye a cualquier rol, anon
-- entre ellos -- por lo que revocar solo de "anon" no alcanzaba:
revoke execute on function public.disparar_procesamiento_documento() from public, anon, authenticated;
revoke execute on function public.generar_respuesta_claude(text, text, integer, text) from public, anon, authenticated;
