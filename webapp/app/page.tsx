"use client";

import { useEffect, useState } from "react";
import { supabase } from "@/lib/supabaseClient";
import Login from "@/components/Login";
import Shell from "@/components/Shell";

export default function Pagina() {
  const [cargandoSesion, setCargandoSesion] = useState(true);
  const [email, setEmail] = useState<string | null>(null);

  async function revisarSesion() {
    const { data: { session } } = await supabase.auth.getSession();
    setEmail(session?.user?.email ?? null);
    setCargandoSesion(false);
  }

  useEffect(() => {
    revisarSesion();
    const { data: suscripcion } = supabase.auth.onAuthStateChange((_evento, session) => {
      setEmail(session?.user?.email ?? null);
    });
    return () => suscripcion.subscription.unsubscribe();
  }, []);

  if (cargandoSesion) return null;

  if (!email) {
    return <Login onIngreso={revisarSesion} />;
  }

  return <Shell email={email} onSalir={() => setEmail(null)} />;
}
