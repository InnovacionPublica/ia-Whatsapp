"use client";

import { useCallback, useEffect, useRef, useState } from "react";
import { supabase } from "@/lib/supabaseClient";
import type { FragmentoPendiente } from "@/lib/types";

export default function TabContenido() {
  const [pendientes, setPendientes] = useState<FragmentoPendiente[]>([]);
  const [seleccionados, setSeleccionados] = useState<Set<string>>(new Set());
  const [cargando, setCargando] = useState(true);
  const [error, setError] = useState("");
  const [mensaje, setMensaje] = useState("");
  const [subiendo, setSubiendo] = useState(false);
  const [generandoEmbeddings, setGenerandoEmbeddings] = useState(false);
  const inputArchivoRef = useRef<HTMLInputElement>(null);

  const cargarPendientes = useCallback(async () => {
    setCargando(true);
    setError("");
    const { data, error } = await supabase.rpc("listar_fragmentos_pendientes");
    setCargando(false);
    if (error) {
      setError("No se pudo cargar la lista: " + error.message);
      return;
    }
    setPendientes(data ?? []);
    setSeleccionados(new Set());
  }, []);

  useEffect(() => {
    cargarPendientes();
  }, [cargarPendientes]);

  async function subirDocumento(archivo: File) {
    setError("");
    setMensaje("");
    setSubiendo(true);

    // Nombre único (prefijo de fecha/hora) para no pisar un archivo
    // existente -- la app solo tiene permiso de subir, no de reemplazar.
    const prefijo = new Date().toISOString().replace(/[:.]/g, "-");
    const nombreLimpio = archivo.name.replace(/[^a-zA-Z0-9._-]/g, "_");
    const ruta = `${prefijo}_${nombreLimpio}`;

    const { error: errorSubida } = await supabase.storage
      .from("documentos-fuente")
      .upload(ruta, archivo);

    setSubiendo(false);

    if (errorSubida) {
      setError("No se pudo subir el archivo: " + errorSubida.message);
      return;
    }

    setMensaje(
      "Archivo subido. El sistema lo está procesando (extrae el texto y lo divide en fragmentos) -- puede tardar unos segundos. Actualizá la lista en breve."
    );

    // El procesamiento es asíncrono (lo dispara un trigger en el backend).
    // Esperamos un momento y refrescamos solos, para no obligar a la
    // usuaria a acordarse de apretar "actualizar".
    setTimeout(cargarPendientes, 4000);
  }

  function alSeleccionarArchivo(e: React.ChangeEvent<HTMLInputElement>) {
    const archivo = e.target.files?.[0];
    if (archivo) subirDocumento(archivo);
    if (inputArchivoRef.current) inputArchivoRef.current.value = "";
  }

  function toggleSeleccion(id: string) {
    setSeleccionados((prev) => {
      const nuevo = new Set(prev);
      if (nuevo.has(id)) nuevo.delete(id);
      else nuevo.add(id);
      return nuevo;
    });
  }

  async function aprobarSeleccionados() {
    if (seleccionados.size === 0) return;
    setError("");
    const { data: { user } } = await supabase.auth.getUser();
    const { error } = await supabase.rpc("aprobar_fragmentos", {
      ids: Array.from(seleccionados),
      aprobado_por: user?.email || "panel_admin",
    });
    if (error) {
      setError("No se pudo aprobar: " + error.message);
      return;
    }
    await cargarPendientes();
  }

  async function aprobarTodo() {
    if (!confirm("¿Aprobar TODO lo pendiente?")) return;
    setError("");
    const { data: { user } } = await supabase.auth.getUser();
    const { error } = await supabase.rpc("aprobar_todo_lo_pendiente", {
      aprobado_por: user?.email || "panel_admin",
    });
    if (error) {
      setError("No se pudo aprobar: " + error.message);
      return;
    }
    await cargarPendientes();
  }

  async function generarEmbeddings() {
    setError("");
    setMensaje("");
    setGenerandoEmbeddings(true);
    const { data, error } = await supabase.rpc("procesar_embeddings_pendientes");
    setGenerandoEmbeddings(false);
    if (error) {
      setError("No se pudo generar los embeddings: " + error.message);
      return;
    }
    setMensaje(
      `Se generaron embeddings para ${data ?? 0} fragmento(s). Sin esto, un fragmento aprobado no puede ser encontrado por la IA.`
    );
  }

  return (
    <div>
      <div className="tarjeta">
        <h2 style={{ fontSize: 16, marginTop: 0 }}>Subir un documento</h2>
        <p className="ayuda">
          Acepta PDF, Word (.docx) o texto plano. El sistema extrae el texto, lo
          divide en fragmentos y los deja "en revisión" más abajo -- nada se
          hace visible para la IA hasta que lo apruebes.
        </p>
        <input
          ref={inputArchivoRef}
          type="file"
          accept=".pdf,.docx,.txt"
          onChange={alSeleccionarArchivo}
          disabled={subiendo}
        />
        {subiendo && <p>Subiendo...</p>}
        <div className="mensaje-error">{error}</div>
        <div className="mensaje-ok">{mensaje}</div>
      </div>

      <div className="tarjeta">
        <div className="barra-superior">
          <h2 style={{ fontSize: 16, margin: 0 }}>
            Fragmentos pendientes de revisión {pendientes.length > 0 && `(${pendientes.length})`}
          </h2>
          <button className="secundario" onClick={cargarPendientes}>
            Actualizar
          </button>
        </div>

        {cargando && <p>Cargando...</p>}

        {!cargando && pendientes.length === 0 && (
          <p style={{ color: "#495057", fontStyle: "italic" }}>
            No hay nada pendiente de revisión.
          </p>
        )}

        {pendientes.map((f) => (
          <div className="fragmento" key={f.id}>
            <label>
              <input
                type="checkbox"
                checked={seleccionados.has(f.id)}
                onChange={() => toggleSeleccion(f.id)}
              />
              <div>
                <div className="meta">{f.tema || ""} · {f.fuente || ""}</div>
                <div>{f.contenido}</div>
              </div>
            </label>
          </div>
        ))}

        {pendientes.length > 0 && (
          <div style={{ display: "flex", gap: 10, marginTop: 16 }}>
            <button onClick={aprobarSeleccionados} disabled={seleccionados.size === 0}>
              Aprobar seleccionados
            </button>
            <button className="secundario" onClick={aprobarTodo}>
              Aprobar todo
            </button>
          </div>
        )}
      </div>

      <div className="tarjeta">
        <h2 style={{ fontSize: 16, marginTop: 0 }}>Embeddings pendientes</h2>
        <p className="ayuda">
          Después de aprobar, cada fragmento necesita un embedding (una
          representación numérica del texto) para que la IA pueda encontrarlo
          cuando alguien pregunte algo relacionado. Este paso es manual porque
          el proveedor (Voyage AI) limita cuántos pedidos por minuto se pueden
          hacer -- puede tardar un momento si hay muchos fragmentos nuevos.
        </p>
        <button className="secundario" onClick={generarEmbeddings} disabled={generandoEmbeddings}>
          {generandoEmbeddings ? "Generando..." : "Generar embeddings pendientes"}
        </button>
      </div>
    </div>
  );
}
