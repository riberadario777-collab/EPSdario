-- 1) Cree su usuario en Supabase > Authentication > Users > Add user (correo y clave).
-- 2) Cambie el correo de abajo por el suyo y ejecute:
update profiles set role='administrador' where id=(select id from auth.users where email='CAMBIAR@CORREO.COM');
