import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { Buffer } from "node:buffer";
import { createClient } from "npm:@supabase/supabase-js@2";
import { extractText } from "npm:unpdf@0.12.1";
import mammoth from "npm:mammoth@1.8.0";

const TAMANO_FRAGMENTO_PALABRAS = 200;

function dividirEnFragmentos(texto: string): string[] {
  const palabras = texto.split(/\s+/).filter(Boolean);
  const fragmentos: string[] = [];
  for (let i = 0; i < palabras.length; i += TAMANO_FRAGMENTO_PALABRAS) {
    const trozo = palabras.slice(i, i + TAMANO_FRAGMENTO_PALABRAS).join(" ");
    if (trozo.trim()) fragmentos.push(trozo);
  }
  return fragmentos;
}

function serializarError(err: unknown) {
  if (err && typeof err === "object") {
    const e = err as Record<string, unknown>;
    return { message: e.message ?? String(err), details: e.details, hint: e.hint, code: e.code };
  }
  return { message: String(err) };
}

Deno.serve(async (req: Request) => {
  try {
    const payload = await req.json();
    const bucket = payload.bucket ?? payload.record?.bucket_id;
    const path = payload.name ?? payload.record?.name;

    if (!bucket || !path) {
      return new Response(JSON.stringify({ error: "Falta bucket o path del archivo" }), { status: 400 });
    }

    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const supabase = createClient(supabaseUrl, serviceKey);

    const storagePath = `${bucket}/${path}`;

    const { data: previo } = await supabase
      .from("documentos_fuente")
      .select("id")
      .eq("storage_path", storagePath);
    if (previo && previo.length > 0) {
      const idsPrevios = previo.map((d: { id: string }) => d.id);
      await supabase.from("fragmentos_conocimiento").delete().in("documento_fuente_id", idsPrevios);
      await supabase.from("documentos_fuente").delete().in("id", idsPrevios);
    }

    const { data: archivo, error: errorDescarga } = await supabase.storage.from(bucket).download(path);
    if (errorDescarga) throw errorDescarga;

    const extension = path.split(".").pop()?.toLowerCase();
    let texto = "";

    if (extension === "pdf") {
      const buffer = new Uint8Array(await archivo.arrayBuffer());
      const resultado = await extractText(buffer, { mergePages: true });
      texto = Array.isArray(resultado.text) ? resultado.text.join("\n") : resultado.text;
    } else if (extension === "docx") {
      const arrayBuffer = await archivo.arrayBuffer();
      const resultado = await mammoth.extractRawText({ buffer: Buffer.from(arrayBuffer) });
      texto = resultado.value;
    } else {
      texto = await archivo.text();
    }

    if (!texto || !texto.trim()) {
      return new Response(JSON.stringify({ error: "No se pudo extraer texto del archivo" }), { status: 422 });
    }

    const nombreArchivo = path.split("/").pop() ?? path;
    const tema = nombreArchivo.replace(/\.[^/.]+$/, "");

    const { data: docRow, error: errorDoc } = await supabase
      .from("documentos_fuente")
      .insert({
        nombre: nombreArchivo,
        tipo_archivo: extension,
        storage_path: storagePath,
        cargado_por: "carga_directa_supabase",
        estado_procesamiento: "procesado",
      })
      .select("id")
      .single();
    if (errorDoc) throw errorDoc;

    const fragmentos = dividirEnFragmentos(texto);
    const filas = fragmentos.map((contenido) => ({
      documento_fuente_id: docRow.id,
      tema,
      contenido,
      fuente: nombreArchivo,
      estado: "en_revision",
    }));

    const { error: errorFragmentos } = await supabase.from("fragmentos_conocimiento").insert(filas);
    if (errorFragmentos) throw errorFragmentos;

    // A PROPÓSITO: ya no se generan los embeddings acá. Extraer el texto y
    // guardarlo en la base de conocimiento es un paso independiente de
    // generarle el embedding para la búsqueda semántica -- eso se hace
    // aparte (procesar_embeddings_pendientes), cuando se decida, sin que
    // un problema con el proveedor de embeddings bloquee la carga del
    // documento en sí.

    return new Response(
      JSON.stringify({ documento: nombreArchivo, fragmentos_insertados: fragmentos.length }),
      { headers: { "Content-Type": "application/json" } },
    );
  } catch (err) {
    return new Response(JSON.stringify({ error: serializarError(err) }), { status: 500 });
  }
});
