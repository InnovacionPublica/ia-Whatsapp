"use client";

import { useState } from "react";
import { supabase } from "@/lib/supabaseClient";

export default function Login({ onIngreso }: { onIngreso: () => void }) {
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [error, setError] = useState("");
  const [cargando, setCargando] = useState(false);

  async function ingresar() {
    setError("");
    setCargando(true);
    const { error } = await supabase.auth.signInWithPassword({
      email: email.trim(),
      password,
    });
    setCargando(false);
    if (error) {
      setError("No se pudo ingresar: " + error.message);
      return;
    }
    onIngreso();
  }

  return (
    <div className="contenedor" style={{ maxWidth: 360, marginTop: 80 }}>
      <div className="tarjeta">
        <h1 style={{ fontSize: 20 }}>Administración del agente</h1>
        <p style={{ fontSize: 13, color: "#495057" }}>
          Ingresá con la cuenta que te invitaron desde Supabase.
        </p>
        <label>Email</label>
        <input
          type="email"
          value={email}
          onChange={(e) => setEmail(e.target.value)}
          onKeyDown={(e) => e.key === "Enter" && ingresar()}
        />
        <label>Contraseña</label>
        <input
          type="password"
          value={password}
          onChange={(e) => setPassword(e.target.value)}
          onKeyDown={(e) => e.key === "Enter" && ingresar()}
        />
        <button onClick={ingresar} disabled={cargando}>
          {cargando ? "Ingresando..." : "Ingresar"}
        </button>
        <div className="mensaje-error">{error}</div>
      </div>
    </div>
  );
}
