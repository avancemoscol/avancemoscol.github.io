-- Migración 0011: Ilustraciones (generadas con Vertex AI) de los referentes
update public.referentes r set imagen_path = v.p
from (values
  ('Antanas Mockus', 'assets/referentes/antanas-mockus.webp'),
  ('Sergio Fajardo', 'assets/referentes/sergio-fajardo.webp'),
  ('Humberto de la Calle', 'assets/referentes/humberto-de-la-calle.webp'),
  ('Claudia López', 'assets/referentes/claudia-lopez.webp'),
  ('Alejandro Gaviria', 'assets/referentes/alejandro-gaviria.webp'),
  ('Emmanuel Macron', 'assets/referentes/emmanuel-macron.webp'),
  ('Angela Merkel', 'assets/referentes/angela-merkel.webp'),
  ('Patricio Aylwin', 'assets/referentes/patricio-aylwin.webp')
) as v(n, p)
where r.nombre = v.n;
