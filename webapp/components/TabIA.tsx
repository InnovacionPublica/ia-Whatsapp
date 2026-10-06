"use client";

import { useEffect, useState } from "react";
import { supabase } from "@/lib/supabaseClient";
import { ConfiguracionAgente, MODELOS_CLAUDE_DISPONIBLES } from "@/lib/types";

function textoAArray(texto: string): string[] {
  return texto
    .split("\n")
    .map((l) => l.trim())
    .filter((l) => l.length > 0);
}

function arrayATexto(arr: string[] | null | undefined): string {
  return (arr ?? []).join("\n");
}

export default function TabIA() {
  const [config, setConfig] = useState<ConfiguracionAgente | null>(null);
  const [cargando, setCargando] = useState(true);
  const [guardando, setGuardando] = useState(false);
  const [error, setError] = useState("");
  const [mensaje, setMensaje] = useState("");

  // Campos editables como texto plano (para los arrays, una frase por línea).
  const [instrucciones, setInstrucciones] = useState("");
  const [umbral, setUmbral] = useState("0.5");
  const [modelo, setModelo] = useState("");
  const [horaInicio, setHoraInicio] = useState("06:00");
  const [horaFin, setHoraFin] = useState("14:00");
  const [frasesPedido, setFrasesPedido] = useState("");
  const [frasesDisconf, setFrasesDisconf] = useState("");
  const [mensajeHorario, setMensajeHorario] = useState("");
  const [mensajeFueraHorario, setMensajeFueraHorario] = useState("");

  useEffect(() => {
    (async () => {
      setCargando(true);
      const { data, error } = await supabase
        .from("configuracion_agente")
        .select("*")
        .eq("id", 1)
        .single();
      setCargando(false);
      if (error) {
        setError("No se pudo cargar la configuración: " + error.message);
        return;
      }
      const c = data as ConfiguracionAgente;
      setConfig(c);
      setInstrucciones(c.instrucciones_sistema);
      setUmbral(String(c.umbral_confianza));
      setModelo(c.modelo_claude);
      setHoraInicio(c.horario_inicio?.slice(0, 5) ?? "06:00");
      setHoraFin(c.horario_fin?.slice(0, 5) ?? "14:00");
      setFrasesPedido(arrayATexto(c.frases_pedido_explicito));
      setFrasesDisconf(arrayATexto(c.frases_disconformidad));
      setMensajeHorario(c.mensaje_derivacion_horario);
      setMensajeFueraHorario(c.mensaje_derivacion_fuera_horario);
    })();
  }, []);

  async function guardar() {
    setError("");
    setMensaje("");

    const umbralNum = parseFloat(umbral.replace(",", "."));
    if (isNaN(umbralNum) || umbralNum <= 0 || umbralNum > 1) {
      setError("El umbral de confianza tiene que ser un número entre 0 (excluido) y 1.");
      return;
    }
    if (horaInicio >= horaFin) {
      setError("El horario de inicio tiene que ser anterior al de fin.");
      return;
    }
    if (!instrucciones.trim()) {
      setError("Las instrucciones del sistema no pueden quedar vacías.");
      return;
    }

    setGuardando(true);
    const { data: { user } } = await supabase.auth.getUser();
    const { data, error } = await supabase.rpc("guardar_configuracion_agente", {
      p_instrucciones_sistema: instrucciones,
      p_umbral_confianza: umbralNum,
      p_modelo_claude: modelo,
      p_horario_inicio: horaInicio,
      p_horario_fin: horaFin,
      p_frases_pedido_explicito: textoAArray(frasesPedido),
      p_frases_disconformidad: textoAArray(frasesDisconf),
      p_mensaje_derivacion_horario: mensajeHorario,
      p_mensaje_derivacion_fuera_horario: mensajeFueraHorario,
      p_actualizado_por: user?.email || "panel_admin",
    });
    setGuardando(false);

    if (error) {
      setError("No se pudo guardar: " + error.message);
      return;
    }
    setConfig(data as ConfiguracionAgente);
    setMensaje("Configuración guardada. Se aplica al próximo mensaje que llegue -- no hace falta reiniciar nada.");
  }

  if (cargando) return <p>Cargando configuración...</p>;

  return (
    <div>
      <div className="tarjeta">
        <h2 style={{ fontSize: 16, marginTop: 0 }}>Instrucciones del sistema</h2>
        <p className="ayuda">
          El texto que le dice a Claude cómo comportarse. Al contexto ya
          aprobado de la base de conocimiento se le agrega esto antes de cada
          respuesta.
        </p>
        <textarea
          rows={6}
          value={instrucciones}
          onChange={(e) => setInstrucciones(e.target.value)}
        />
      </div>

      <div className="tarjeta">
        <h2 style={{ fontSize: 16, marginTop: 0 }}>Umbral de confianza y modelo</h2>
        <label>Umbral de confianza (entre 0 y 1)</label>
        <p className="ayuda">
          Si la similitud con el fragmento más parecido es menor a este
          valor, se deriva a una persona en vez de responder. Valor actual
          del sistema: 0.50.
        </p>
        <input value={umbral} onChange={(e) => setUmbral(e.target.value)} />

        <label>Modelo de Claude</label>
        <select value={modelo} onChange={(e) => setModelo(e.target.value)}>
          {MODELOS_CLAUDE_DISPONIBLES.map((m) => (
            <option key={m} value={m}>
              {m}
            </option>
          ))}
          {!MODELOS_CLAUDE_DISPONIBLES.includes(modelo) && (
            <option value={modelo}>{modelo} (actual)</option>
          )}
        </select>
      </div>

      <div className="tarjeta">
        <h2 style={{ fontSize: 16, marginTop: 0 }}>Horario de atención humana</h2>
        <p className="ayuda">
          Fuera de este horario, una derivación queda "pendiente" en vez de
          pasar directo a un operador.
        </p>
        <div style={{ display: "flex", gap: 16 }}>
          <div style={{ flex: 1 }}>
            <label>Desde</label>
            <input type="time" value={horaInicio} onChange={(e) => setHoraInicio(e.target.value)} />
          </div>
          <div style={{ flex: 1 }}>
            <label>Hasta</label>
            <input type="time" value={horaFin} onChange={(e) => setHoraFin(e.target.value)} />
          </div>
        </div>
      </div>

      <div className="tarjeta">
        <h2 style={{ fontSize: 16, marginTop: 0 }}>Frases de derivación</h2>
        <p className="ayuda">
          Una frase por línea. Si el mensaje del ciudadano contiene alguna de
          estas frases, se deriva a una persona sin pasar por la IA.
        </p>
        <label>Pedido explícito de hablar con una persona</label>
        <textarea rows={5} value={frasesPedido} onChange={(e) => setFrasesPedido(e.target.value)} />
        <label>Señales de disconformidad</label>
        <textarea rows={5} value={frasesDisconf} onChange={(e) => setFrasesDisconf(e.target.value)} />
      </div>

      <div className="tarjeta">
        <h2 style={{ fontSize: 16, marginTop: 0 }}>Mensajes de derivación</h2>
        <label>Cuando hay un operador disponible (dentro del horario)</label>
        <textarea rows={3} value={mensajeHorario} onChange={(e) => setMensajeHorario(e.target.value)} />
        <label>Cuando no hay operadores (fuera del horario)</label>
        <textarea rows={3} value={mensajeFueraHorario} onChange={(e) => setMensajeFueraHorario(e.target.value)} />
      </div>

      <button onClick={guardar} disabled={guardando}>
        {guardando ? "Guardando..." : "Guardar cambios"}
      </button>
      {config?.actualizado_por && (
        <p className="ayuda" style={{ marginTop: 10 }}>
          Última actualización: {config.actualizado_por} · {new Date(config.actualizado_en).toLocaleString("es-AR")}
        </p>
      )}
      <div className="mensaje-error">{error}</div>
      <div className="mensaje-ok">{mensaje}</div>
    </div>
  );
}
