# Agente de WhatsApp para atención ciudadana — Secretaría de Gestión Pública (Santa Fe)

Este repositorio guarda el código versionado del proyecto: el panel de aprobación de contenido y las funciones de backend (Supabase). La base de datos, la autenticación y el hosting de las funciones siguen viviendo en Supabase; este repositorio es la fuente de verdad del código, y desde acá se van a ir desplegando los cambios (en vez de editar directo en los paneles de Supabase o Cloudflare).

## Estructura

```
panel/
  index.html          Panel web de aprobación de contenido (login + lista de fragmentos pendientes).
                       Se despliega en Cloudflare Pages: https://panel-aprobacion-sgp.pages.dev

supabase/
  functions/
    whatsapp-webhook/      Edge Function: recibe los mensajes de WhatsApp (Meta Cloud API) y llama
                            al orquestador (procesar_mensaje_ciudadano) y al envío de respuestas.
    procesar-documento/    Edge Function: cuando se sube un documento a Storage, extrae el texto
                            (PDF o Word), lo divide en fragmentos y los guarda como "en_revision".
  sql/
    01_aprobacion.sql            Aprobar fragmentos (uno, por documento, o todos los pendientes).
    02_embeddings_voyage.sql     Generar embeddings (Voyage AI) y buscar fragmentos por similitud.
    03_respuesta_claude.sql      Generar la respuesta final con Claude (Anthropic).
    04_whatsapp.sql              Enviar mensajes por WhatsApp y verificar el token del webhook.
    05_conversaciones.sql        Pasar una conversación a "ia" o registrar la respuesta de un operador.
    06_orquestador.sql           procesar_mensaje_ciudadano: la función principal que decide qué
                                  hacer con cada mensaje entrante (responder, derivar, o bloquear
                                  porque ya la está atendiendo un operador).
```

## Principio de diseño (no cambia)

El sistema nunca responde con información que no haya sido cargada y aprobada antes por el equipo (fragmentos con `estado = 'activo'`). Si no hay evidencia suficiente, si piden hablar con una persona, o si hay señales de disconformidad, la conversación se deriva a un operador humano (o queda "pendiente" fuera del horario de atención, 6 a 14 hs). El detalle completo de las reglas está comentado dentro de `supabase/sql/06_orquestador.sql`.

## Secretos

Ninguna clave (Meta, Voyage AI, Anthropic) está en este repositorio ni en el código. Las funciones de `supabase/sql/` las leen en tiempo de ejecución desde Supabase Vault (`vault.decrypted_secrets`), por nombre. Para aplicar estos archivos a un proyecto de Supabase hace falta tener cargados en Vault los secretos: `meta_whatsapp_token`, `meta_phone_number_id`, `meta_verify_token`, `voyage_api_key`, `anthropic_api_key`.

## Historia de decisiones y estado del proyecto

El detalle de cómo se llegó a cada decisión (arquitectura, alternativas evaluadas, qué falta) se documenta aparte, en el Proyecto de Claude "Agente IA WhatsApp" (`arquitectura-tecnica.md` y `guia-simple-del-proyecto.md`), no en este repositorio.
