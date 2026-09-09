import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";

// Webhook de WhatsApp (Cloud API directa de Meta, sin BSP -- Etapa 17).
// GET: handshake de verificacion que exige Meta al configurar el webhook.
// POST: mensajes entrantes reales de ciudadanos.
// verify_jwt=false a proposito: Meta no manda nuestro JWT de Supabase; la
// autenticacion real es el hub.verify_token (GET) -- la firma de Meta
// (X-Hub-Signature-256) queda pendiente de sumar cuando tengamos el App Secret.

Deno.serve(async (req: Request) => {
  const supabase = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );

  if (req.method === "GET") {
    const url = new URL(req.url);
    const modo = url.searchParams.get("hub.mode");
    const token = url.searchParams.get("hub.verify_token");
    const desafio = url.searchParams.get("hub.challenge");

    if (modo === "subscribe" && token) {
      const { data: valido } = await supabase.rpc("verificar_token_whatsapp", { token_recibido: token });
      if (valido) {
        return new Response(desafio ?? "", { status: 200 });
      }
    }
    return new Response("Verificacion fallida", { status: 403 });
  }

  if (req.method !== "POST") {
    return new Response("Metodo no soportado", { status: 405 });
  }

  try {
    const payload = await req.json();

    // Estructura tipica del webhook de Meta:
    // entry[].changes[].value.messages[] = { from, id, timestamp, type, text: { body } }
    const mensajes = payload?.entry?.[0]?.changes?.[0]?.value?.messages ?? [];

    for (const msg of mensajes) {
      if (msg.type !== "text") {
        // Por ahora solo se procesan mensajes de texto; otros tipos
        // (audio, imagen, ubicacion, etc.) quedan fuera de esta primera version.
        continue;
      }

      const ciudadanoId = msg.from as string;
      const mensajeTexto = msg.text?.body as string;
      if (!ciudadanoId || !mensajeTexto) continue;

      const { data: resultado, error: errorProceso } = await supabase.rpc("procesar_mensaje_ciudadano", {
        p_ciudadano_id: ciudadanoId,
        p_mensaje: mensajeTexto,
      });

      if (errorProceso) {
        console.error("Error procesando mensaje:", errorProceso);
        continue;
      }

      const respuestaTexto = resultado?.respuesta as string | null;
      if (respuestaTexto) {
        const { error: errorEnvio } = await supabase.rpc("enviar_mensaje_whatsapp", {
          destino: ciudadanoId,
          texto: respuestaTexto,
        });
        if (errorEnvio) {
          console.error("Error enviando respuesta por WhatsApp:", errorEnvio);
        }
      }
    }

    // Meta espera un 200 rapido para no reintentar el webhook.
    return new Response(JSON.stringify({ ok: true }), { headers: { "Content-Type": "application/json" } });
  } catch (err) {
    console.error("Error en webhook de WhatsApp:", err);
    // Igual devolvemos 200 para que Meta no reintente en bucle un payload
    // que ya sabemos que no vamos a poder procesar.
    return new Response(JSON.stringify({ ok: false }), { headers: { "Content-Type": "application/json" } });
  }
});
