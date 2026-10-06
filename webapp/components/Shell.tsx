"use client";

import { useState } from "react";
import { supabase } from "@/lib/supabaseClient";
import TabContenido from "./TabContenido";
import TabIA from "./TabIA";
import TabWhatsapp from "./TabWhatsapp";

type Pestana = "contenido" | "ia" | "whatsapp";

export default function Shell({ email, onSalir }: { email: string; onSalir: () => void }) {
  const [pestana, setPestana] = useState<Pestana>("contenido");

  async function salir() {
    await supabase.auth.signOut();
    onSalir();
  }

  return (
    <div className="contenedor">
      <div className="barra-superior">
        <h1 style={{ fontSize: 20 }}>Administración del agente WhatsApp</h1>
        <div style={{ display: "flex", alignItems: "center", gap: 12 }}>
          <span style={{ fontSize: 13, color: "#495057" }}>{email}</span>
          <button className="secundario" onClick={salir}>
            Salir
          </button>
        </div>
      </div>

      <div className="pestanas">
        <div
          className={`pestana ${pestana === "contenido" ? "activa" : ""}`}
          onClick={() => setPestana("contenido")}
        >
          Contenido
        </div>
        <div className={`pestana ${pestana === "ia" ? "activa" : ""}`} onClick={() => setPestana("ia")}>
          IA
        </div>
        <div
          className={`pestana ${pestana === "whatsapp" ? "activa" : ""}`}
          onClick={() => setPestana("whatsapp")}
        >
          WhatsApp
        </div>
      </div>

      {pestana === "contenido" && <TabContenido />}
      {pestana === "ia" && <TabIA />}
      {pestana === "whatsapp" && <TabWhatsapp />}
    </div>
  );
}
