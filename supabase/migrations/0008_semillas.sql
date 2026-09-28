-- =============================================================================
-- Migración 0008: Semillas de Datos Iniciales (Territorio, CMS, Referentes, Propuestas)
-- Plataforma Avancemos · Movimiento Político de Centro (Colombia)
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. Departamentos (32 Departamentos + Bogotá D.C.)
-- -----------------------------------------------------------------------------
insert into public.departamentos (id, nombre, slug, region, capital_id) values
  ('05', 'Antioquia', 'antioquia', 'Andina', '05001'),
  ('08', 'Atlántico', 'atlantico', 'Caribe', '08001'),
  ('11', 'Bogotá D. C.', 'bogota', 'Andina', '11001'),
  ('13', 'Bolívar', 'bolivar', 'Caribe', '13001'),
  ('15', 'Boyacá', 'boyaca', 'Andina', '15001'),
  ('17', 'Caldas', 'caldas', 'Andina', '17001'),
  ('18', 'Caquetá', 'caqueta', 'Amazonía', '18001'),
  ('19', 'Cauca', 'cauca', 'Pacífica', '19001'),
  ('20', 'Cesar', 'cesar', 'Caribe', '20001'),
  ('23', 'Córdoba', 'cordoba', 'Caribe', '23001'),
  ('25', 'Cundinamarca', 'cundinamarca', 'Andina', '11001'),
  ('27', 'Chocó', 'choco', 'Pacífica', '27001'),
  ('41', 'Huila', 'huila', 'Andina', '41001'),
  ('44', 'La Guajira', 'la-guajira', 'Caribe', '44001'),
  ('47', 'Magdalena', 'magdalena', 'Caribe', '47001'),
  ('50', 'Meta', 'meta', 'Orinoquía', '50001'),
  ('52', 'Nariño', 'narino', 'Pacífica', '52001'),
  ('54', 'Norte de Santander', 'norte-de-santander', 'Andina', '54001'),
  ('63', 'Quindío', 'quindio', 'Andina', '63001'),
  ('66', 'Risaralda', 'risaralda', 'Andina', '66001'),
  ('68', 'Santander', 'santander', 'Andina', '68001'),
  ('70', 'Sucre', 'sucre', 'Caribe', '70001'),
  ('73', 'Tolima', 'tolima', 'Andina', '73001'),
  ('76', 'Valle del Cauca', 'valle-del-cauca', 'Pacífica', '76001'),
  ('81', 'Arauca', 'arauca', 'Orinoquía', '81001'),
  ('85', 'Casanare', 'casanare', 'Orinoquía', '85001'),
  ('86', 'Putumayo', 'putumayo', 'Amazonía', '86001'),
  ('88', 'Archipiélago de San Andrés, Providencia y Santa Catalina', 'san-andres', 'Insular', '88001'),
  ('91', 'Amazonas', 'amazonas', 'Amazonía', '91001'),
  ('94', 'Guainía', 'guainia', 'Amazonía', '94001'),
  ('95', 'Guaviare', 'guaviare', 'Amazonía', '95001'),
  ('97', 'Vaupés', 'vaupes', 'Amazonía', '97001'),
  ('99', 'Vichada', 'vichada', 'Orinoquía', '99001')
on conflict (id) do update set
  nombre = excluded.nombre,
  slug = excluded.slug,
  region = excluded.region,
  capital_id = excluded.capital_id;

-- -----------------------------------------------------------------------------
-- 2. Capitales de Departamento
-- -----------------------------------------------------------------------------
insert into public.municipios (id, departamento_id, nombre, slug, es_capital) values
  ('05001', '05', 'Medellín', 'medellin', true),
  ('08001', '08', 'Barranquilla', 'barranquilla', true),
  ('11001', '11', 'Bogotá D. C.', 'bogota', true),
  ('13001', '13', 'Cartagena de Indias', 'cartagena', true),
  ('15001', '15', 'Tunja', 'tunja', true),
  ('17001', '17', 'Manizales', 'manizales', true),
  ('18001', '18', 'Florencia', 'florencia', true),
  ('19001', '19', 'Popayán', 'popayan', true),
  ('20001', '20', 'Valledupar', 'valledupar', true),
  ('23001', '23', 'Montería', 'monteria', true),
  ('27001', '27', 'Quibdó', 'quibdo', true),
  ('41001', '41', 'Neiva', 'neiva', true),
  ('44001', '44', 'Riohacha', 'riohacha', true),
  ('47001', '47', 'Santa Marta', 'santa-marta', true),
  ('50001', '50', 'Villavicencio', 'villavicencio', true),
  ('52001', '52', 'Pasto', 'pasto', true),
  ('54001', '54', 'Cúcuta', 'cucuta', true),
  ('63001', '63', 'Armenia', 'armenia', true),
  ('66001', '66', 'Pereira', 'pereira', true),
  ('68001', '68', 'Bucaramanga', 'bucaramanga', true),
  ('70001', '70', 'Sincelejo', 'sincelejo', true),
  ('73001', '73', 'Ibagué', 'ibague', true),
  ('76001', '76', 'Cali', 'cali', true),
  ('81001', '81', 'Arauca', 'arauca', true),
  ('85001', '85', 'Yopal', 'yopal', true),
  ('86001', '86', 'Mocoa', 'mocoa', true),
  ('88001', '88', 'San Andrés', 'san-andres', true),
  ('91001', '91', 'Leticia', 'leticia', true),
  ('94001', '94', 'Inírida', 'inirida', true),
  ('95001', '95', 'San José del Guaviare', 'san-jose-del-guaviare', true),
  ('97001', '97', 'Mitú', 'mitu', true),
  ('99001', '99', 'Puerto Carreño', 'puerto-carreno', true)
on conflict (id) do nothing;

-- -----------------------------------------------------------------------------
-- 3. Localidades de Bogotá (20)
-- -----------------------------------------------------------------------------
insert into public.localidades_bogota (id, nombre) values
  (1, 'Usaquén'),
  (2, 'Chapinero'),
  (3, 'Santa Fe'),
  (4, 'San Cristóbal'),
  (5, 'Usme'),
  (6, 'Tunjuelito'),
  (7, 'Bosa'),
  (8, 'Kennedy'),
  (9, 'Fontibón'),
  (10, 'Engativá'),
  (11, 'Suba'),
  (12, 'Barrios Unidos'),
  (13, 'Teusaquillo'),
  (14, 'Los Mártires'),
  (15, 'Antonio Nariño'),
  (16, 'Puente Aranda'),
  (17, 'La Candelaria'),
  (18, 'Rafael Uribe Uribe'),
  (19, 'Ciudad Bolívar'),
  (20, 'Sumapaz')
on conflict (id) do nothing;

-- -----------------------------------------------------------------------------
-- 4. Configuración Global de la Plataforma
-- -----------------------------------------------------------------------------
insert into public.configuracion (clave, valor) values
  ('general', '{
    "auto_aprobacion_roles": ["admin_departamental", "admin_nacional"],
    "roles_pueden_publicar": ["voluntario", "lider", "moderador", "admin_departamental", "admin_nacional"],
    "limites": {
      "publicaciones_dia": 10,
      "publicaciones_dia_nuevos": 3,
      "comentarios_hora": 30,
      "conversaciones_nuevas_dia": 20,
      "conversaciones_nuevas_dia_nuevos": 5,
      "dias_usuario_nuevo": 7
    },
    "umbral_privacidad_mapa": 5,
    "contadores_inicio_minimo": 100,
    "visibilidad_grupos_whatsapp": "mi_departamento_y_nacionales",
    "verificacion": { "dias_antiguedad": 30, "dias_sin_sancion": 90 },
    "ia_cuotas_diarias": {
      "miembro": { "textos": 30 },
      "admin_departamental": { "imagenes": 20, "videos": 2, "textos": 100 },
      "admin_nacional": { "imagenes": 60, "videos": 10, "textos": 300 }
    },
    "ia_estilo_marca": "warm natural light, subtle teal and amber tones, editorial documentary photography, dignified and optimistic, realistic, no text, no logos",
    "ia_terminos_bloqueados": [],
    "motivos_rechazo": [
      "Ataque personal o lenguaje ofensivo",
      "Información sin fuente o engañosa",
      "Datos personales de terceros",
      "Contenido de campaña que requiere revisión jurídica",
      "No corresponde al territorio o alcance elegido",
      "Spam, publicidad comercial o cadena",
      "Imagen o video inapropiado o de baja calidad",
      "Duplicado",
      "Otro"
    ],
    "eliminacion_cuenta": "anonimizar",
    "modo_campana": false,
    "modo_mantenimiento": false
  }'::jsonb)
on conflict (clave) do update set valor = excluded.valor;

-- -----------------------------------------------------------------------------
-- 5. Propuestas Ejes de Avancemos
-- -----------------------------------------------------------------------------
insert into public.propuestas (eje, titulo, resumen, detalle_md, icono, orden, publicada) values
  ('educacion', 'Educación de calidad desde la primera infancia', 'Fortalecimiento de la educación pública rural y urbana, jornada única con nutrición y formación docente de excelencia.', '### Prioridad nacional: Educación\nLa educación es la principal herramienta para cerrar brechas de inequidad en Colombia. Proponemos:\n- Atención integral a la primera infancia en los 32 departamentos.\n- Infraestructura digna, conectividad digital y bibliotecas comunitarias.\n- Dignificación de la carrera docente con formación continua y estímulos por desempeño.', 'graduation-cap', 1, true),
  ('seguridad', 'Seguridad ciudadana con Estado de derecho', 'Seguridad humana, justicia cercana y fortalecimiento institucional para proteger la vida en campos y ciudades.', '### Seguridad y Convivencia\nSin seguridad no hay libertad ni desarrollo. Planteamos:\n- Fortalecimiento de la policía comunitaria y cuadrantes inteligentes.\n- Desarticulación de economías ilícitas con tecnología e inteligencia financiera.\n- Acceso expedito a la justicia local y resolución pacífica de conflictos.', 'shield', 2, true),
  ('empleo', 'Empleo, emprendimiento y formalización', 'Reducción de trabas tributarias para microempresas, crédito accesible y fomento de sectores estratégicos.', '### Oportunidades y Crecimiento Sostenible\nEl trabajo digno es la base del bienestar familiar:\n- Ventanilla única de formalización con tarifas escalonadas para pymes.\n- Inclusión financiera rural y fondos de garantía para jóvenes emprendedores.\n- Alianzas público-privadas en ciencia, tecnología e industrias verdes.', 'briefcase', 3, true),
  ('transparencia', 'Transparencia y lucha contra la corrupción', 'Cero tolerancia con la corrupción, datos abiertos en contratación pública y protección al denunciante.', '### Cero Corrupción, Máxima Eficiencia\nLos recursos públicos son sagrados:\n- Pliegos tipo obligatorios en todos los niveles de gobierno.\n- Rendición de cuentas en tiempo real y auditorías ciudadanas digitales.\n- Muerte política definitiva y extinción de dominio ágil a corruptos.', 'eye', 4, true),
  ('salud', 'Salud cercana y sostenible', 'Sistema mixto con giro directo, enfoque preventivo y fortalecimiento de hospitales públicos.', '### Salud Oportuna y de Calidad\nLa salud es un derecho fundamental irrenunciable:\n- Red de atención primaria preventiva en zonas dispersas y rurales.\n- Control riguroso a precios de medicamentos de alto costo.\n- Sostenibilidad financiera y pago oportuno al talento humano de la salud.', 'heart-pulse', 5, true),
  ('campo', 'Campo, agua y transición energética', 'Desarrollo agropecuario sostenible, protección de fuentes hídricas y transición energética justa y técnica.', '### El Campo como Motor de Vida\nUn país que cuida su agua y cultiva su futuro:\n- Titulación y acceso a crédito para pequeños y medianos campesinos.\n- Vías terciarias construidas con comités comunitarios para sacar cosechas.\n- Transición energética gradual y con rigor técnico, sin poner en riesgo la economía.', 'leaf', 6, true),
  ('paz', 'Paz, convivencia y reconciliación', 'Cumplimiento serio de acuerdos, presencia integral del Estado y protección efectiva a líderes sociales.', '### Convivencia Democrática\nUna sociedad que dialoga y resuelve sus diferencias:\n- Implementación rigurosa de los programas territoriales de desarrollo (PDET).\n- Rutas inmediatas de protección comunitaria para líderes sociales y ambientales.\n- Pedagogía para la reconciliación y memoria histórica sin sesgos ideológicos.', 'handshake', 7, true),
  ('territorio', 'Territorios conectados: movilidad, vivienda y conectividad', 'Integración de las regiones mediante infraestructura multimodal, vivienda digna e internet de alta velocidad.', '### Conexión Territorial Real\nSuperar el aislamiento geográfico de Colombia:\n- Red de conectividad digital satelital y fibra óptica en municipios apartados.\n- Mejoramiento integral de vivienda y titulación de predios urbanos y rurales.\n- Movilidad sostenible, trenes de cercanías y navegabilidad fluvial.', 'network', 8, true)
on conflict do nothing;

-- -----------------------------------------------------------------------------
-- 6. Referentes de Centro (Colombia y Mundo)
-- -----------------------------------------------------------------------------
insert into public.referentes (nombre, ambito, pais, orientacion, cargos, logros, contexto, leccion, fuentes, orden, publicado) values
  ('Antanas Mockus', 'colombia', 'Colombia', 'Centro', 'Alcalde de Bogotá (1995–1997, 2001–2003)',
   array['Cultura ciudadana con mimos y pedagogía en las calles', 'Reducción histórica de homicidios en Bogotá', 'Programa voluntario 110% con Bogotá donde 63.000 ciudadanos pagaron más impuestos'],
   'Demostró que el cambio cultural y el respeto por las normas salvan más vidas que la sola coerción.',
   'La pedagogía, la confianza ciudadana y la integridad pueden transformar una sociedad.',
   array['https://es.wikipedia.org/wiki/Antanas_Mockus'], 1, true),

  ('Sergio Fajardo', 'colombia', 'Colombia', 'Centro', 'Alcalde de Medellín (2004–2007), Gobernador de Antioquia (2012–2015)',
   array['Medellín, la más educada: Parques Biblioteca y urbanismo social', 'Antioquia la más educada con 80 parques educativos', '23.7% en primera vuelta presidencial de 2018 como alternativa de centro'],
   'El urbanismo social llevó lo más bello a las zonas más vulnerables de Medellín.',
   'La educación y la cultura son el motor central para superar la violencia y la desigualdad.',
   array['https://es.wikipedia.org/wiki/Sergio_Fajardo'], 2, true),

  ('Humberto de la Calle', 'colombia', 'Colombia', 'Centro liberal', 'Jefe Negociador de Paz (2012–2016), Vicepresidente (1994–1996), Ministro de Gobierno (1990–1993)',
   array['Coordinó desde el Gobierno la Asamblea Nacional Constituyente de 1991', 'Lideró la negociación paciente del Acuerdo de Paz con las FARC en La Habana', 'Defensa constante de la Constitución y las libertades civiles'],
   'La concertación y la paciencia son indispensables para terminar décadas de conflicto armado.',
   'El diálogo riguroso e institucional puede resolver las diferencias más profundas de una nación.',
   array['https://es.wikipedia.org/wiki/Humberto_de_La_Calle'], 3, true),

  ('Claudia López', 'colombia', 'Colombia', 'Centroizquierda', 'Alcaldesa de Bogotá (2020–2023), Senadora (2014–2018)',
   array['Impulso a la Consulta Anticorrupción de 2018 con 11.7 millones de votos', 'Creación del Sistema Distrital de Cuidado y Manzanas del Cuidado', 'Inversión en educación superior gratuita Jóvenes a la U'],
   'Primera mujer elegida por voto popular en Bogotá; gobernó durante la pandemia del COVID-19.',
   'Convertir las causas ciudadanas y de equidad en instituciones públicas concretas y duraderas.',
   array['https://es.wikipedia.org/wiki/Claudia_L%C3%B3pez_Hern%C3%A1ndez'], 4, true),

  ('Alejandro Gaviria', 'colombia', 'Colombia', 'Centro', 'Ministro de Salud (2012–2018), Rector Universidad de los Andes (2019–2021)',
   array['Ley Estatutaria de Salud (Ley 1751 de 2015) reconociendo la salud como derecho fundamental', 'Control de precios de medicamentos y caso Imatinib en defensa del bolsillo público', 'Liderazgo en debates con evidencia técnica y rigor académico'],
   'Enfrentó intereses de multinacionales farmacéuticas basándose en evidencia científica y económica.',
   'Tomar decisiones técnicas fundamentadas en datos, aun frente a presiones de sectores poderosos.',
   array['https://es.wikipedia.org/wiki/Alejandro_Gaviria'], 5, true),

  ('Emmanuel Macron', 'mundo', 'Francia', 'Centro liberal', 'Presidente de Francia (2017–actualidad)',
   array['Fundación del movimiento ciudadano En Marche! superando la polarización tradicional', 'Campaña de escucha ciudadana puerta a puerta en toda Francia', 'Reducción del tamaño de aulas en zonas escolares vulnerables'],
   'Llegó al gobierno con un movimiento nuevo creado desde las bases ciudadanas.',
   'Un movimiento nuevo puede consolidarse rápido escuchando a la gente en el territorio y proponiendo acuerdos.',
   array['https://es.wikipedia.org/wiki/Emmanuel_Macron'], 6, true),

  ('Angela Merkel', 'mundo', 'Alemania', 'Centroderecha moderada', 'Canciller de Alemania (2005–2021)',
   array['16 años de gobierno liderando en gran coalición con socialdemócratas', 'Implementación del salario mínimo nacional en Alemania (2015)', 'Manejo equilibrado y técnico de las crisis financieras europeas'],
   'Conocida por su estilo sobrio, pragmático y capacidad de construcción de consensos.',
   'La moderación, la sobriedad y la concertación entre adversarios dan estabilidad a largo plazo.',
   array['https://es.wikipedia.org/wiki/Angela_Merkel'], 7, true),

  ('Patricio Aylwin', 'mundo', 'Chile', 'Centro (Democracia Cristiana)', 'Presidente de Chile (1990–1994)',
   array['Lideró la transición pacífica a la democracia encabezando la Concertación', 'Creó la Comisión Nacional de Verdad y Reconciliación (Informe Rettig)', 'Logró un crecimiento económico récord reduciendo la pobreza significativamente'],
   'Condujo una transición histórica con firmeza democrática y serenidad institucional.',
   'La reconciliación democrática y los resultados económicos de bienestar pueden avanzar de la mano.',
   array['https://es.wikipedia.org/wiki/Patricio_Aylwin'], 8, true)
on conflict do nothing;

-- -----------------------------------------------------------------------------
-- 7. Contenido Semilla de Páginas CMS
-- -----------------------------------------------------------------------------
insert into public.paginas (slug, titulo, contenido_md, seo_titulo, seo_descripcion, publicada) values
  ('el-centro', 'El Centro Político: Filosofía y Evidencia',
   '# ¿Qué es el centro político?\n\nEl centro es la posición que busca soluciones prácticas tomando lo que funciona de distintas tradiciones políticas, en lugar de aplicar una ideología cerrada o caer en fanatismos.\n\n### Rasgos principales:\n1. **Pragmatismo y evidencia**: las políticas públicas se juzgan por sus resultados medibles, no por dogmas.\n2. **Diálogo y acuerdos**: se construyen consensos amplios en lugar de imponer desde trincheras ideológicas.\n3. **Instituciones y Estado de derecho**: respeto absoluto por la Constitución de 1991 y la separación de poderes.\n4. **Economía social de mercado**: impulso al emprendimiento y crecimiento económico con fuerte redistribución que reduzca la desigualdad.\n5. **Reformas graduales y evaluables**: progreso sostenible sin rupturas destructivas.\n6. **Integridad ética**: la lucha contra la corrupción como principio no negociable.\n\n### Lo que el centro NO es:\n- **No es tibieza**: toma posición clara en cada tema analizando la evidencia.\n- **No es un promedio automático**: no se trata de dividir la diferencia, sino de encontrar la mejor solución técnica y humana.\n- **No es apolítico**: es una forma de hacer política basada en el respeto ciudadano y los resultados.\n\n### Hitos del centro en Colombia:\n- **1991 — Constitución Política**: nacida de un acuerdo histórico entre fuerzas diversas (Serpa, Gómez Hurtado, Navarro Wolff).\n- **2010 — La Ola Verde**: pedagogía cívica y voluntariado ciudadano masivo.\n- **2018 — Consulta Anticorrupción**: casi 12 millones de votos ciudadanos por la transparencia.',
   'El Centro Político · Avancemos Colombia',
   'Descubre qué es el centro político, sus fundamentos filosóficos, evidencia empírica e hitos históricos en Colombia y el mundo.',
   true),

  ('quienes-somos', 'Quiénes Somos · Avancemos',
   '# Movimiento Político Avancemos\n\nSomos un movimiento ciudadano, descentralizado y de centro, presente en los 32 departamentos de Colombia y Bogotá.\n\n### Misión\nOrganizar a ciudadanos de todas las regiones para construir y ejecutar soluciones prácticas, basadas en evidencia y en acuerdos, que mejoren la vida de los colombianos.\n\n### Visión\nUna Colombia que resuelve sus problemas con diálogo, instituciones confiables y resultados medibles, sin extremos ni polarización estéril.\n\n### Nuestros Valores:\n- **Pragmatismo**: Lo que funciona, respaldado por datos.\n- **Diálogo**: Acuerdos reales por encima de trincheras.\n- **Integridad**: Cero tolerancia con la corrupción.\n- **Respeto**: A la diferencia, a las minorías y a las instituciones.\n- **Territorio**: Decisiones pensadas desde las regiones, no desde un escritorio central.',
   'Quiénes Somos · Movimiento Avancemos Colombia',
   'Conoce la misión, visión, valores y estructura del movimiento político de centro Avancemos en Colombia.',
   true),

  ('normas', 'Normas de la Comunidad Avancemos',
   '# Normas de Convivencia y Participación\n\n1. **Debate ideas, no ataques a personas**: Prohibido el insulto, el acoso y la descalificación personal.\n2. **Cero discursos de odio**: Cero tolerancia a la discriminación por motivos de género, raza, orientación, religión o condición social.\n3. **Cita fuentes y respeta la verdad**: No difundas noticias falsas, desinformación o montajes.\n4. **Protege la privacidad**: No publiques datos personales (teléfonos, direcciones, documentos) de terceros.\n5. **No a la suplantación**: Identidad real, transparente y verificable.\n6. **Sin spam ni cadenas**: El contenido debe aportar valor cívico, debate constructivo o coordinación comunitaria.\n7. **Respeta las decisiones de moderación**: Puedes apelar formalmente a través del sistema si consideras un error.',
   'Normas de la Comunidad · Avancemos',
   'Reglas de respeto, diálogo y convivencia democrática en la plataforma Avancemos.',
   true),

  ('privacidad', 'Política de Tratamiento de Datos Personales',
   '# Política de Privacidad y Tratamiento de Datos (Ley 1581 de 2012)\n\nEn **Avancemos**, la privacidad de nuestros simpatizantes, voluntarios y líderes es prioritaria, especialmente en el contexto social y democrático de Colombia.\n\n### 1. Responsable del Tratamiento\nMovimiento Político Avancemos Colombia.\nCorreo de atención: abulingo.help@gmail.com\n\n### 2. Datos Sensibles y Finalidad\nLa orientación o pertenencia política constituye un dato sensible conforme al Decreto 1377 de 2013. Su tratamiento es estrictamente voluntario y tiene como única finalidad la coordinación interna de actividades ciudadanas, participación en eventos y deliberación democrática.\n\n### 3. Derechos del Titular (Habeas Data)\nTienes derecho a conocer, actualizar, rectificar y solicitar la supresión de tus datos, así como a descargar una copia completa en formato JSON desde los ajustes de tu cuenta.',
   'Política de Privacidad · Avancemos',
   'Cumplimiento de la Ley 1581 de 2012 y protección reforzada de datos de simpatizantes y líderes.',
   true),

  ('terminos', 'Términos y Condiciones de Uso',
   '# Términos de Uso de la Plataforma Avancemos\n\nBienvenido a la plataforma oficial de Avancemos. Al registrarte o navegar en el sitio aceptas los presentes términos:\n- La plataforma está destinada exclusivamente a mayores de 18 años.\n- Los usuarios son responsables de las publicaciones y comentarios que realizan.\n- Avancemos se reserva el derecho de moderar, suspender o cancelar cuentas que violen las normas de la comunidad o la ley colombiana.\n- El contenido generado con inteligencia artificial se encuentra claramente etiquetado conforme a los estándares de transparencia.',
   'Términos y Condiciones · Avancemos',
   'Condiciones legales de uso de la plataforma digital Avancemos.',
   true)
on conflict (slug) do update set
  titulo = excluded.titulo,
  contenido_md = excluded.contenido_md,
  seo_titulo = excluded.seo_titulo,
  seo_descripcion = excluded.seo_descripcion,
  publicada = excluded.publicada;
