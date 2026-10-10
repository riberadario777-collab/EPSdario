-- Ejecutar DESPUÉS de SQL_6 (SQL Editor > Run)
alter table products add column if not exists min_stock int not null default 0;
alter table company_settings add column if not exists max_discount numeric not null default 5;
alter table orders add column if not exists discount_pct numeric not null default 0 check(discount_pct>=0 and discount_pct<=100);
create or replace function chk_discount() returns trigger language plpgsql security definer set search_path=public as $$ begin
 if new.discount_pct>(select max_discount from company_settings) and not has_role('{administrador}') then raise exception 'El descuento supera el máximo autorizado'; end if; return new; end $$;
create trigger t_disc before insert or update on orders for each row execute function chk_discount();
create or replace view order_balance with (security_invoker=true) as
select o.id order_id, o.number, c.name client,
 coalesce(t.total,0)*(1-coalesce(o.discount_pct,0)/100)+case when o.transport_charged then coalesce(o.transport,0) else 0 end+coalesce(o.extras,0) as total,
 coalesce(p.paid,0) as paid
from orders o join clients c on c.id=o.client_id
left join (select order_id,sum(amount) total from order_items group by 1) t on t.order_id=o.id
left join (select order_id,sum(amount) paid from payments group by 1) p on p.order_id=o.id;
create or replace function tg_disp() returns trigger language plpgsql security definer set search_path=public as $$ declare v numeric; p numeric; d numeric; begin
 select oi.volume_piece,oi.price_m3,o.discount_pct into v,p,d from order_items oi join orders o on o.id=oi.order_id where oi.id=new.item_id;
 perform auto_entry('Venta por despacho','AUTO-VENTA '||new.id,'1.2','4.1',new.qty*v*p*(1-d/100));
 perform auto_entry('Costo de venta por despacho','AUTO-COSTO '||new.id,'5.1','1.3',new.qty*v*new.cost_m3); return new; end $$;
create or replace view product_stock as
select p.id product_id,p.code,p.espesor,p.largo,p.ancho,p.min_stock,inv.physical,coalesce(r.res,0) reserved,inv.physical-coalesce(r.res,0) available,inv.physical<=p.min_stock as low,inv.physical*p.volume_piece as m3
from products p join inventory inv on inv.product_id=p.id
left join (select i.product_id, sum(i.qty-coalesce((select sum(d.qty) from dispatches d where d.item_id=i.id),0)) res from order_items i where exists(select 1 from schedule s where s.order_id=i.order_id and s.status='pendiente') group by 1) r on r.product_id=p.id
where is_staff();
grant select on product_stock to authenticated;
create or replace function schedule_delivery(p_order uuid,p_day date,p_vol numeric) returns void language plpgsql security definer set search_path=public as $$
declare used numeric; r record; av numeric; begin
 if not has_role('{administrador,despacho,ventas}') then raise exception 'Sin permiso'; end if;
 perform pg_advisory_xact_lock(hashtext(p_day::text));
 select coalesce(sum(volume),0) into used from schedule where day=p_day and status='pendiente';
 if used+p_vol>120 then raise exception 'Excede 120 m3 el %: usado % m3',p_day,used; end if;
 if not exists(select 1 from schedule where order_id=p_order and status='pendiente') then
  perform pg_advisory_xact_lock(777);
  for r in select i.product_id, i.qty-coalesce((select sum(d.qty) from dispatches d where d.item_id=i.id),0) pend from order_items i where i.order_id=p_order loop
   select available into av from product_stock where product_id=r.product_id;
   if r.pend>av then raise exception 'Stock disponible insuficiente: faltan % piezas',r.pend-av; end if; end loop;
 end if;
 insert into schedule(order_id,day,volume) values(p_order,p_day,p_vol);
 insert into audit(action,detail) values('schedule',jsonb_build_object('order',p_order,'day',p_day,'vol',p_vol)); end $$;
create or replace function cancel_schedule(p_id uuid) returns void language plpgsql security definer set search_path=public as $$ begin
 if not has_role('{administrador,despacho,ventas}') then raise exception 'Sin permiso'; end if;
 update schedule set status='cancelado' where id=p_id and status='pendiente';
 insert into audit(action,detail) values('schedule_cancel',jsonb_build_object('id',p_id)); end $$;
create or replace function reschedule(p_id uuid,p_day date) returns void language plpgsql security definer set search_path=public as $$
declare s schedule; used numeric; begin
 if not has_role('{administrador,despacho,ventas}') then raise exception 'Sin permiso'; end if;
 perform pg_advisory_xact_lock(hashtext(p_day::text));
 select * into s from schedule where id=p_id and status='pendiente' for update;
 if not found then raise exception 'La programación no existe o no está pendiente'; end if;
 select coalesce(sum(volume),0) into used from schedule where day=p_day and status='pendiente' and id<>p_id;
 if used+s.volume>120 then raise exception 'Excede 120 m3 el %: usado % m3',p_day,used; end if;
 update schedule set day=p_day where id=p_id;
 insert into audit(action,detail) values('reschedule',jsonb_build_object('id',p_id,'day',p_day)); end $$;
