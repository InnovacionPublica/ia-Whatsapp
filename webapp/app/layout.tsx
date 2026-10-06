import "./globals.css";
import type { Metadata } from "next";

export const metadata: Metadata = {
  title: "Administración — Agente WhatsApp SGP",
  description: "Carga de información, configuración de la IA y credenciales de WhatsApp.",
};

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="es">
      <body>{children}</body>
    </html>
  );
}
