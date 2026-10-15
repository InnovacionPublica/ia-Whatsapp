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

const MARCADOR_FRAGMENTO = /^=== FRAGMENTO ===\s*$/m;

type FragmentoEstructurado = {
  tema: string | null;
  preguntas_frecuentes: string | null;
  contenido: string;
  informacion_adicional: string | null;
  organismo: string | null;
  url_oficial: string | null;
  vigencia: string | null;
  fuente: string | null;
};

// Campos reconocidos (sin tildes, en mayúsculas) -> columna de la tabla.
const CAMPOS: Record<string, keyof FragmentoEstructurado> = {
  "TEMA": "tema",
  "PREGUNTAS FRECUENTES": "preguntas_frecuentes",
  "CONTENIDO": "contenido",
  "INFORMACION ADICIONAL": "informacion_adicional",
  "ORGANISMO": "organismo",
  "URL OFICIAL": "url_oficial",
  "VIGENCIA": "vigencia",
  "FUENTE": "fuente",
};

function sinTildes(t: string): string {
  return t.normalize("NFD").replace(/[\u0300-\u036f]/g, "");
}

// Si el archivo trae bloques "=== FRAGMENTO ===" con campos "CLAVE: valor",
// se respeta esa estructura (un bloque = un fragmento). Si no, el llamador
// usa el corte automático por cantidad de palabras.
function parsearFragmentosEstructurados(texto: string): { fragmentos: FragmentoEstructurado[]; advertencias: string[] } {
  const advertencias: string[] = [];
  const fragmentos: FragmentoEstructurado[] = [];
  // Lo que haya antes del primer marcador (portada, introducción) se descarta.
  const partes = texto.split(MARCADOR_FRAGMENTO);
  partes.shift();
  const bloques = partes.map((b) => b.trim());

  bloques.forEach((bloque, idx) => {
    const valores: Partial<Record<keyof FragmentoEstructurado, string[]>> = {};
    let actual: keyof FragmentoEstructurado | null = null;

    for (const linea of bloque.split(/\r?\n/)) {
      const m = linea.match(/^\s*([A-Za-zÁÉÍÓÚÜÑáéíóúüñ ]{3,30}):\s*(.*)$/);
      const clave = m ? sinTildes(m[1]).toUpperCase().trim() : null;
      if (m && clave && CAMPOS[clave]) {
        actual = CAMPOS[clave];
        valores[actual] = [m[2]];
      } else if (actual) {
        valores[actual]!.push(linea);
      }
    }

    const campo = (k: keyof FragmentoEstructurado): string | null => {
      const v = (valores[k] ?? []).join("\n").trim();
      return v ? v : null;
    };

    const contenido = campo("contenido");
    if (!contenido) {
      advertencias.push(`Bloque ${idx + 1}: sin campo CONTENIDO, se omitió.`);
      return;
    }

    let vigencia = campo("vigencia");
    if (vigencia && !/^\d{4}-\d{2}-\d{2}$/.test(vigencia)) {
      advertencias.push(`Bloque ${idx + 1}: VIGENCIA "${vigencia}" no tiene formato AAAA-MM-DD, se ignoró.`);
      vigencia = null;
    }

    fragmentos.push({
      tema: campo("tema"),
      preguntas_frecuentes: campo("preguntas_frecuentes"),
      contenido,
      informacion_adicional: campo("informacion_adicional"),
      organismo: campo("organismo"),
      url_oficial: campo("url_oficial"),
      vigencia,
      fuente: campo("fuente"),
    });
  });

  return { fragmentos, advertencias };
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

    let advertencias: string[] = [];
    let filas;
    if (MARCADOR_FRAGMENTO.test(texto)) {
      const r = parsearFragmentosEstructurados(texto);
      advertencias = r.advertencias;
      if (r.fragmentos.length === 0) {
        await supabase.from("documentos_fuente").delete().eq("id", docRow.id);
        return new Response(
          JSON.stringify({ error: "El archivo tiene marcadores de fragmento pero ninguno es válido", advertencias }),
          { status: 422 },
        );
      }
      filas = r.fragmentos.map((f) => ({
        documento_fuente_id: docRow.id,
        tema: f.tema ?? tema,
        preguntas_frecuentes: f.preguntas_frecuentes,
        contenido: f.contenido,
        informacion_adicional: f.informacion_adicional,
        organismo: f.organismo,
        url_oficial: f.url_oficial,
        vigencia: f.vigencia,
        fuente: f.fuente ?? nombreArchivo,
        estado: "en_revision",
      }));
    } else {
      filas = dividirEnFragmentos(texto).map((contenido) => ({
        documento_fuente_id: docRow.id,
        tema,
        contenido,
        fuente: nombreArchivo,
        estado: "en_revision",
      }));
    }

    const { error: errorFragmentos } = await supabase.from("fragmentos_conocimiento").insert(filas);
    if (errorFragmentos) throw errorFragmentos;

    // A PROPÓSITO: ya no se generan los embeddings acá. Extraer el texto y
    // guardarlo en la base de conocimiento es un paso independiente de
    // generarle el embedding para la búsqueda semántica -- eso se hace
    // aparte (procesar_embeddings_pendientes), cuando se decida, sin que
    // un problema con el proveedor de embeddings bloquee la carga del
    // documento en sí.

    return new Response(
      JSON.stringify({ documento: nombreArchivo, fragmentos_insertados: filas.length, advertencias }),
      { headers: { "Content-Type": "application/json" } },
    );
  } catch (err) {
    return new Response(JSON.stringify({ error: serializarError(err) }), { status: 500 });
  }
});
