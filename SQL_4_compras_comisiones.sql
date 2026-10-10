-- Ejecutar DESPUÉS de SQL_3 (SQL Editor > Run)
alter table products add column if not exists avg_cost_m3 numeric not null default 0;
alter table dispatches add column if not exists cost_m3 numeric not null default 0;
create table suppliers(id uuid primary key default gen_random_uuid(), name text not null, phone text, created_at timestamptz default now());
create table purchases(id uuid primary key default gen_random_uuid(), number bigint generated always as identity, supplier_id uuid not null references suppliers, doc text, status text not null default 'borrador', created_by uuid default auth.uid(), created_at timestamptz default now());
create table purchase_items(id uuid primary key default gen_random_uuid(), purchase_id uuid not null references purchases on delete cascade, product_id uuid not null references products, qty int not null check(qty>0), cost_m3 numeric not null check(cost_m3>=0));
create table sellers(id uuid primary key default gen_random_uuid(), name text not null, phone text, created_at timestamptz default now());
create table commissions(id uuid primary key default gen_random_uuid(), order_id uuid not null references orders, seller_id uuid not null references sellers, kind text not null check(kind in('fijo','porcentaje')), value numeric not null check(value>=0), amount numeric, paid_at timestamptz, created_at timestamptz default now());
create or replace function calc_commission() returns trigger language plpgsql security definer set search_path=public as $$ begin
 if new.kind='fijo' then new.amount=new.value; else select new.value/100*total into new.amount from order_balance where order_id=new.order_id; end if; return new; end $$;
create trigger t_comm before insert on commissions for each row execute function calc_commission();
create or replace function receive_purchase(p_id uuid) returns void language plpgsql security definer set search_path=public as $$
declare pu purchases; it record; vp numeric; ph int; ac numeric; begin
 if not has_role('{administrador,almacen}') then raise exception 'Sin permiso'; end if;
 select * into pu from purchases where id=p_id for update;
 if pu.status<>'borrador' then raise exception 'Compra ya recibida'; end if;
 for it in select * from purchase_items where purchase_id=p_id loop
  select volume_piece,avg_cost_m3 into vp,ac from products where id=it.product_id for update;
  select physical into ph from inventory where product_id=it.product_id for update;
  update products set avg_cost_m3=(ph*vp*ac+it.qty*vp*it.cost_m3)/((ph+it.qty)*vp) where id=it.product_id;
  update inventory set physical=physical+it.qty where product_id=it.product_id;
 end loop;
 update purchases set status='recibida' where id=p_id;
 insert into audit(action,detail) values('purchase_received',jsonb_build_object('purchase',p_id)); end $$;
create or replace function pay_commission(p_id uuid) returns void language plpgsql security definer set search_path=public as $$ begin
 if not has_role('{administrador,contabilidad}') then raise exception 'Sin permiso'; end if;
 update commissions set paid_at=now() where id=p_id and paid_at is null;
 insert into audit(action,detail) values('commission_paid',jsonb_build_object('id',p_id)); end $$;
create or replace function register_dispatch(p_item uuid,p_qty int,p_key text) returns void language plpgsql security definer set search_path=public as $$
declare it order_items; done int; stock int; cost numeric; begin
 if not has_role('{administrador,despacho}') then raise exception 'Sin permiso'; end if;
 select * into it from order_items where id=p_item for update;
 select coalesce(sum(qty),0) into done from dispatches where item_id=p_item;
 if done+p_qty>it.qty then raise exception 'Supera lo solicitado (saldo %)',it.qty-done; end if;
 select physical into stock from inventory where product_id=it.product_id for update;
 if stock<p_qty then raise exception 'Stock insuficiente (%)',stock; end if;
 select avg_cost_m3 into cost from products where id=it.product_id;
 insert into dispatches(item_id,qty,idem_key,cost_m3) values(p_item,p_qty,p_key,cost);
 update inventory set physical=physical-p_qty where product_id=it.product_id;
 insert into audit(action,detail) values('dispatch',jsonb_build_object('item',p_item,'qty',p_qty)); end $$;
alter table suppliers enable row level security; alter table purchases enable row level security; alter table purchase_items enable row level security; alter table sellers enable row level security; alter table commissions enable row level security;
create policy su_sel on suppliers for select using(has_role('{administrador,almacen,contabilidad}')); create policy su_w on suppliers for insert with check(has_role('{administrador,almacen}'));
create policy pu_sel on purchases for select using(has_role('{administrador,almacen,contabilidad}')); create policy pu_w on purchases for insert with check(has_role('{administrador,almacen}'));
create policy pi_sel on purchase_items for select using(has_role('{administrador,almacen,contabilidad}')); create policy pi_w on purchase_items for insert with check(has_role('{administrador,almacen}') and exists(select 1 from purchases where id=purchase_id and status='borrador'));
create policy se_sel on sellers for select using(has_role('{administrador,ventas,contabilidad}')); create policy se_w on sellers for insert with check(has_role('{administrador,ventas}'));
create policy co_sel on commissions for select using(has_role('{administrador,ventas,contabilidad}')); create policy co_w on commissions for insert with check(has_role('{administrador,ventas}'));
create or replace view utilidad_mensual with (security_invoker=true) as
select m.mes, coalesce(v.x,0) ingresos, coalesce(c.x,0) costo_material, coalesce(k.x,0) comisiones, coalesce(t.x,0) transporte_empresa
from (select distinct date_trunc('month',created_at)::date mes from orders) m
left join (select date_trunc('month',o.created_at)::date mes, sum(b.total) x from orders o join order_balance b on b.order_id=o.id group by 1) v using(mes)
left join (select date_trunc('month',d.created_at)::date mes, sum(d.qty*i.volume_piece*d.cost_m3) x from dispatches d join order_items i on i.id=d.item_id group by 1) c using(mes)
left join (select date_trunc('month',created_at)::date mes, sum(amount) x from commissions group by 1) k using(mes)
left join (select date_trunc('month',created_at)::date mes, sum(transport) x from orders where not transport_charged group by 1) t using(mes);
grant select on utilidad_mensual to authenticated;
