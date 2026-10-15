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
  modo_pruebas: boolean;
  palabra_activacion: string;
  palabra_salida: string;
  horas_activacion: number;
  actualizado_por: string | null;
  actualizado_en: string;
};

export type EstadoCredencial = {
  nombre: "meta_whatsapp_token" | "meta_phone_number_id" | "meta_verify_token" | "meta_app_secret";
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
  {
    nombre: "meta_app_secret",
    etiqueta: "Clave secreta de la app (App Secret)",
    ayuda:
      "En Meta for Developers: Configuración de la app → Básica → Clave secreta de la app. Se usa para comprobar que cada mensaje recibido realmente viene de Meta. Sin ella, el webhook rechaza todos los mensajes.",
  },
];
