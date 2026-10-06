export type FragmentoPendiente = {
  id: string;
  tema: string | null;
  contenido: string;
  fuente: string | null;
};

export type ConfiguracionAgente = {
  id: number;
  instrucciones_sistema: string;
  umbral_confianza: number;
  modelo_claude: string;
  horario_inicio: string; // "HH:MM:SS"
  horario_fin: string;
  frases_pedido_explicito: string[];
  frases_disconformidad: string[];
  mensaje_derivacion_horario: string;
  mensaje_derivacion_fuera_horario: string;
  actualizado_por: string | null;
  actualizado_en: string;
};

export type EstadoCredencial = {
  nombre: "meta_whatsapp_token" | "meta_phone_number_id" | "meta_verify_token";
  cargada: boolean;
};

export const MODELOS_CLAUDE_DISPONIBLES = [
  "claude-haiku-4-5-20251001",
  "claude-sonnet-4-5-20250929",
  "claude-opus-4-5-20251101",
];

export const NOMBRES_CREDENCIALES_META: {
  nombre: EstadoCredencial["nombre"];
  etiqueta: string;
  ayuda: string;
}[] = [
  {
    nombre: "meta_whatsapp_token",
    etiqueta: "Token de acceso (Meta)",
    ayuda: "El token permanente de la app de WhatsApp Business en Meta for Developers.",
  },
  {
    nombre: "meta_phone_number_id",
    etiqueta: "ID del número de WhatsApp",
    ayuda: "El Phone Number ID que asigna Meta al número conectado.",
  },
  {
    nombre: "meta_verify_token",
    etiqueta: "Token de verificación del webhook",
    ayuda: "Un texto que vos elegís y que también se configura en Meta al dar de alta el webhook.",
  },
];
