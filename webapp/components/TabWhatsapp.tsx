"use client";

import { useEffect, useState } from "react";
import { supabase } from "@/lib/supabaseClient";
import { EstadoCredencial, NOMBRES_CREDENCIALES_META } from "@/lib/types";

export default function TabWhatsapp() {
  const [estados, setEstados] = useState<EstadoCredencial[]>([]);
  const [cargando, setCargando] = useState(true);
  const [valores, setValores] = useState<Record<string, string>>({});
  const [guardando, setGuardando] = useState<string | null>(null);
  const [error, setError] = useState("");
  const [mensaje, setMensaje] = useState("");

  async function cargarEstados() {
    setCargando(true);
    setError("");
    const { data, error } = await supabase.rpc("estado_credenciales_meta");
    setCargando(false);
    if (error) {
      setError("No se pudo consultar el estado de las credenciales: " + error.message);
      return;
    }
    setEstados(data ?? []);
  }

  useEffect(() => {
    cargarEstados();
  }, []);

  function estaCargada(nombre: string) {
    return estados.find((e) => e.nombre === nombre)?.cargada ?? false;
  }

  async function guardarCredencial(nombre: string) {
    const valor = (valores[nombre] || "").trim();
    if (!valor) {
      setError("Ingresá un valor antes de guardar.");
      return;
    }
    setError("");
    setMensaje("");
    setGuardando(nombre);
    const { data: { user } } = await supabase.auth.getUser();
    const { error } = await supabase.rpc("guardar_credencial_meta", {
      p_nombre: nombre,
      p_valor: valor,
      p_actualizado_por: user?.email || "panel_admin",
    });
    setGuardando(null);
    if (error) {
      setError("No se pudo guardar: " + error.message);
      return;
    }
    setValores((prev) => ({ ...prev, [nombre]: "" }));
    setMensaje("Credencial guardada en Supabase Vault (cifrada). No vuelve a mostrarse en pantalla.");
    await cargarEstados();
  }

  return (
    <div>
      <div className="tarjeta">
        <h2 style={{ fontSize: 16, marginTop: 0 }}>Credenciales de WhatsApp (Meta)</h2>
        <p className="ayuda">
          Se guardan cifradas en Supabase Vault -- nunca se muestran de nuevo
          una vez guardadas, ni acá ni en ningún otro lugar. Para
          cambiar una, simplemente ingresá el valor nuevo.
        </p>

        {cargando && <p>Consultando estado...</p>}

        {!cargando &&
          NOMBRES_CREDENCIALES_META.map(({ nombre, etiqueta, ayuda }) => (
            <div key={nombre} style={{ marginBottom: 18, paddingBottom: 14, borderBottom: "1px solid #f1f3f5" }}>
              <label>
                {etiqueta}{" "}
                {estaCargada(nombre) ? (
                  <span className="chip ok">cargada</span>
                ) : (
                  <span className="chip falta">falta cargar</span>
                )}
              </label>
              <p className="ayuda" style={{ marginTop: -6 }}>{ayuda}</p>
              <div style={{ display: "flex", gap: 8 }}>
                <input
                  type="password"
                  placeholder={estaCargada(nombre) ? "Ingresar un valor nuevo para reemplazarla" : "Pegar el valor acá"}
                  value={valores[nombre] || ""}
                  onChange={(e) => setValores((prev) => ({ ...prev, [nombre]: e.target.value }))}
                  style={{ margin: 0 }}
                />
                <button
                  className="secundario"
                  onClick={() => guardarCredencial(nombre)}
                  disabled={guardando === nombre}
                  style={{ whiteSpace: "nowrap" }}
                >
                  {guardando === nombre ? "Guardando..." : "Guardar"}
                </button>
              </div>
            </div>
          ))}

        <div className="mensaje-error">{error}</div>
        <div className="mensaje-ok">{mensaje}</div>
      </div>
    </div>
  );
}
