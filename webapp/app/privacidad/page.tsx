import type { Metadata } from "next";

export const metadata: Metadata = {
  title: "Política de privacidad — Asistente de atención ciudadana por WhatsApp",
  description:
    "Cómo trata los datos personales el asistente de atención ciudadana por WhatsApp de la Secretaría de Gestión Pública de la Provincia de Santa Fe.",
};

const seccion: React.CSSProperties = { marginTop: 28 };
const titulo: React.CSSProperties = { fontSize: 18, marginBottom: 6 };
const parrafo: React.CSSProperties = { lineHeight: 1.6, margin: "8px 0" };

export default function PoliticaDePrivacidad() {
  return (
    <main className="contenedor" style={{ maxWidth: 760 }}>
      <h1 style={{ fontSize: 26, marginBottom: 4 }}>Política de privacidad</h1>
      <p style={{ ...parrafo, color: "#495057" }}>
        Asistente de atención ciudadana por WhatsApp — Secretaría de Gestión Pública, Ministerio de
        Gobierno e Innovación Pública, Provincia de Santa Fe.
      </p>
      <p style={{ ...parrafo, color: "#868e96", fontSize: 13 }}>
        Versión 1 — última actualización: 14 de octubre de 2026.
      </p>

      <section style={seccion}>
        <h2 style={titulo}>1. Quién es responsable</h2>
        <p style={parrafo}>
          El responsable del tratamiento de los datos es la Secretaría de Gestión Pública del
          Ministerio de Gobierno e Innovación Pública de la Provincia de Santa Fe, que brinda este
          servicio de atención por WhatsApp.
        </p>
      </section>

      <section style={seccion}>
        <h2 style={titulo}>2. Qué datos se tratan</h2>
        <p style={parrafo}>
          Cuando escribís al servicio se registran: tu número de teléfono de WhatsApp, el texto de
          los mensajes que enviás, la fecha y la hora, la respuesta que recibís y la decisión que
          tomó el sistema (por ejemplo, responder o derivar a una persona). No se solicitan ni se
          necesitan datos sensibles para usar el servicio; te pedimos que no los incluyas en tus
          mensajes.
        </p>
      </section>

      <section style={seccion}>
        <h2 style={titulo}>3. Para qué se usan</h2>
        <p style={parrafo}>
          Los datos se usan para responder tus consultas sobre trámites y servicios de la
          Provincia, para derivarlas a una persona del equipo cuando corresponda, y para mantener
          un registro de control y trazabilidad que permita auditar y mejorar el servicio. No se
          usan con fines publicitarios ni comerciales.
        </p>
      </section>

      <section style={seccion}>
        <h2 style={titulo}>4. Cómo funciona el asistente</h2>
        <p style={parrafo}>
          Las respuestas las redacta un sistema de inteligencia artificial, que utiliza únicamente
          información previamente revisada y aprobada por la Secretaría. Si no hay información
          suficiente para responder con seguridad, o si pedís hablar con una persona, la consulta se
          deriva a una persona del equipo. Aun así, el asistente puede equivocarse: ante una
          decisión importante, verificá la información en los canales oficiales de la Provincia en
          santafe.gob.ar.
        </p>
      </section>

      <section style={seccion}>
        <h2 style={titulo}>5. Con quién se comparten los datos</h2>
        <p style={parrafo}>
          Para prestar el servicio se utilizan proveedores tecnológicos que procesan datos en
          nombre de la Secretaría: Meta (WhatsApp Business Platform), que transporta los mensajes;
          Supabase, que aloja la base de datos del servicio; Anthropic, que procesa el texto de tu
          consulta para redactar la respuesta (a este proveedor no se le envía tu número de
          teléfono); y Vercel, que aloja el panel de administración del equipo. Algunos de estos
          proveedores pueden estar ubicados o procesar datos fuera de la República Argentina. No se
          venden ni se ceden tus datos a terceros para otros fines.
        </p>
      </section>

      <section style={seccion}>
        <h2 style={titulo}>6. Cuánto tiempo se conservan</h2>
        <p style={parrafo}>
          Las conversaciones se conservan con fines de atención, control y auditoría durante el
          plazo que establezca la Secretaría conforme a la normativa aplicable. El acceso a esa
          información está limitado al personal autorizado.
        </p>
      </section>

      <section style={seccion}>
        <h2 style={titulo}>7. Tus derechos y cómo ejercerlos</h2>
        <p style={parrafo}>
          Conforme a la Ley N.º 25.326 de Protección de los Datos Personales y normas concordantes,
          podés solicitar el acceso a tus datos, su rectificación o su supresión. Para hacerlo,
          comunicate con la Secretaría de Gestión Pública a través de los canales oficiales de
          contacto publicados en santafe.gob.ar, indicando el número de teléfono desde el que
          escribiste. También podés pedir, desde esa misma vía, la eliminación de los datos
          asociados a tu número.
        </p>
      </section>

      <section style={seccion}>
        <h2 style={titulo}>8. Seguridad</h2>
        <p style={parrafo}>
          Las credenciales del servicio se almacenan cifradas, los mensajes recibidos desde WhatsApp
          se validan antes de procesarse y el acceso al panel de administración requiere
          autenticación. Ningún sistema es infalible; ante cualquier incidente que afecte tus datos
          se actuará conforme a la normativa vigente.
        </p>
      </section>

      <section style={seccion}>
        <h2 style={titulo}>9. Cambios en esta política</h2>
        <p style={parrafo}>
          Si esta política cambia, se publicará la nueva versión en esta misma dirección con su
          fecha de actualización.
        </p>
      </section>
    </main>
  );
}
