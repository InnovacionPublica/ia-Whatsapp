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
