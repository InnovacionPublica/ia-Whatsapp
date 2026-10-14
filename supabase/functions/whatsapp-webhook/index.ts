import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";

// Webhook de WhatsApp (Cloud API directa de Meta, sin BSP -- Etapa 17).
// GET: handshake de verificacion que exige Meta al configurar el webhook.
// POST: mensajes entrantes reales de ciudadanos.
// verify_jwt=false a proposito: Meta no manda nuestro JWT de Supabase. La
// autenticacion real es:
//   - GET: hub.verify_token contra el guardado en Vault.
//   - POST: firma HMAC-SHA256 (X-Hub-Signature-256) calculada por Meta con el
//     App Secret sobre el cuerpo crudo. Si el App Secret no esta cargado o la
//     firma no coincide, el mensaje se rechaza (fail-closed).
// Ademas, cada mensaje se registra por su id (mensajes_procesados) para no
// responder dos veces si Meta reintenta la entrega.

const codificador = new TextEncoder();

function aHex(buffer: ArrayBuffer): string {
  return [...new Uint8Array(buffer)].map((b) => b.toString(16).padStart(2, "0")).join("");
}

// Comparacion en tiempo constante para no filtrar informacion por tiempos de respuesta.
function igualesEnTiempoConstante(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let diferencia = 0;
  for (let i = 0; i < a.length; i++) {
    diferencia |= a.charCodeAt(i) ^ b.charCodeAt(i);
  }
  return diferencia === 0;
}

async function firmaValida(cuerpo: Uint8Array, cabecera: string | null, secreto: string): Promise<boolean> {
  if (!cabecera || !cabecera.startsWith("sha256=")) return false;
  const clave = await crypto.subtle.importKey(
    "raw",
    codificador.encode(secreto),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const firma = await crypto.subtle.sign("HMAC", clave, cuerpo);
  return igualesEnTiempoConstante(aHex(firma), cabecera.slice("sha256=".length).trim().toLowerCase());
}

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

  // 1) Validar la firma sobre el cuerpo crudo, antes de leer su contenido.
  const cuerpoCrudo = new Uint8Array(await req.arrayBuffer());

  const { data: secreto, error: errorSecreto } = await supabase.rpc("obtener_app_secret_whatsapp");
  if (errorSecreto || !secreto) {
    console.error("App Secret de Meta no disponible; se rechaza el mensaje.", errorSecreto);
    // 503: es un problema nuestro; Meta reintenta y el mensaje se procesa cuando se cargue el secreto.
    return new Response("Servicio no configurado", { status: 503 });
  }

  const firmaOk = await firmaValida(cuerpoCrudo, req.headers.get("x-hub-signature-256"), secreto as string);
  if (!firmaOk) {
    console.error("Firma de Meta invalida; mensaje rechazado.");
    return new Response("Firma invalida", { status: 403 });
  }

  // 2) Procesar los mensajes.
  let reintentar = false;
  try {
    const payload = JSON.parse(new TextDecoder().decode(cuerpoCrudo));

    // Estructura tipica del webhook de Meta:
    // entry[].changes[].value.messages[] = { from, id, timestamp, type, text: { body } }
    for (const entrada of payload?.entry ?? []) {
      for (const cambio of entrada?.changes ?? []) {
        const mensajes = cambio?.value?.messages ?? [];

        for (const msg of mensajes) {
          if (msg.type !== "text") {
            // Por ahora solo se procesan mensajes de texto; otros tipos
            // (audio, imagen, ubicacion, etc.) quedan fuera de esta primera version.
            continue;
          }

          const ciudadanoId = msg.from as string;
          const mensajeTexto = msg.text?.body as string;
          if (!ciudadanoId || !mensajeTexto) continue;

          // Anti-duplicados: si ya procesamos este id, no se responde de nuevo.
          if (msg.id) {
            const { data: esNuevo, error: errorRegistro } = await supabase.rpc("registrar_mensaje_entrante", {
              p_id: msg.id as string,
            });
            if (errorRegistro) {
              console.error("Error registrando el mensaje entrante:", errorRegistro);
              reintentar = true; // pedimos a Meta que reintente; con la base disponible se deduplica bien
              continue;
            }
            if (!esNuevo) continue;
          }

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
      }
    }
  } catch (err) {
    console.error("Error en webhook de WhatsApp:", err);
    // Igual devolvemos 200 para que Meta no reintente en bucle un payload
    // que ya sabemos que no vamos a poder procesar.
    return new Response(JSON.stringify({ ok: false }), { headers: { "Content-Type": "application/json" } });
  }

  if (reintentar) {
    return new Response("Reintentar", { status: 500 });
  }
  // Meta espera un 200 rapido para no reintentar el webhook.
  return new Response(JSON.stringify({ ok: true }), { headers: { "Content-Type": "application/json" } });
});
