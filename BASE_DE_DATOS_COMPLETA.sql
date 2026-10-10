-- Pegar completo en Supabase > SQL Editor > Run
create type app_role as enum ('administrador','ventas','despacho','almacen','contabilidad','sin_rol');
create table profiles(id uuid primary key references auth.users on delete cascade, full_name text, role app_role not null default 'sin_rol', active boolean not null default true);
create or replace function my_role() returns app_role language sql security definer stable set search_path=public as $$ select role from profiles where id=auth.uid() and active $$;
create or replace function has_role(r app_role[]) returns boolean language sql security definer stable set search_path=public as $$ select coalesce(my_role()=any(r),false) $$;
create or replace function is_staff() returns boolean language sql security definer stable set search_path=public as $$ select coalesce(my_role() not in ('sin_rol'),false) $$;
create or replace function handle_new_user() returns trigger language plpgsql security definer set search_path=public as $$ begin insert into profiles(id,full_name) values(new.id,new.email); return new; end $$;
create trigger on_auth_user after insert on auth.users for each row execute function handle_new_user();

create table clients(id uuid primary key default gen_random_uuid(), name text not null, nit_ci text, phone text, email text, address text, created_at timestamptz default now());
create table products(id uuid primary key default gen_random_uuid(), code text unique not null, name text not null, espesor numeric not null check(espesor>0), largo numeric not null check(largo>0), ancho numeric not null check(ancho>0),
  price_m3 numeric not null check(price_m3>=0), active boolean default true, created_at timestamptz default now(),
  volume_piece numeric(14,6) generated always as (espesor*largo*ancho/1000000) stored);
create table inventory(product_id uuid primary key references products on delete cascade, physical int not null default 0 check(physical>=0), reserved int not null default 0);
create or replace function new_product_inv() returns trigger language plpgsql as $$ begin insert into inventory(product_id) values(new.id); return new; end $$;
create trigger t_prod_inv after insert on products for each row execute function new_product_inv();

create table orders(id uuid primary key default gen_random_uuid(), number bigint generated always as identity, client_id uuid not null references clients, with_invoice boolean default false,
  transport numeric default 0, transport_charged boolean default true, extras numeric default 0, commission numeric default 0, status text default 'pendiente', created_by uuid default auth.uid(), created_at timestamptz default now());
create table order_items(id uuid primary key default gen_random_uuid(), order_id uuid not null references orders on delete cascade, product_id uuid not null references products,
  qty int not null check(qty>0), price_m3 numeric, volume_piece numeric(14,6), amount numeric generated always as (qty*volume_piece*price_m3) stored);
create or replace function snap_item() returns trigger language plpgsql as $$ begin select price_m3,volume_piece into new.price_m3,new.volume_piece from products where id=new.product_id; return new; end $$;
create trigger t_snap before insert on order_items for each row execute function snap_item();

create table schedule(id uuid primary key default gen_random_uuid(), order_id uuid not null references orders, day date not null, volume numeric not null check(volume>0), status text default 'pendiente', created_by uuid default auth.uid());
create table dispatches(id uuid primary key default gen_random_uuid(), item_id uuid not null references order_items, qty int not null check(qty>0), idem_key text unique, user_id uuid default auth.uid(), created_at timestamptz default now());
create table payments(id uuid primary key default gen_random_uuid(), order_id uuid not null references orders, amount numeric not null check(amount>0), method text, created_by uuid default auth.uid(), created_at timestamptz default now());
create table audit(id bigint generated always as identity primary key, who uuid default auth.uid(), action text, detail jsonb, at timestamptz default now());

create or replace function schedule_delivery(p_order uuid,p_day date,p_vol numeric) returns void language plpgsql security definer set search_path=public as $$
declare used numeric; begin
 if not has_role('{administrador,despacho,ventas}') then raise exception 'Sin permiso'; end if;
 perform pg_advisory_xact_lock(hashtext(p_day::text));
 select coalesce(sum(volume),0) into used from schedule where day=p_day and status='pendiente';
 if used+p_vol>120 then raise exception 'Excede 120 m3 el %: usado % m3',p_day,used; end if;
 insert into schedule(order_id,day,volume) values(p_order,p_day,p_vol);
 insert into audit(action,detail) values('schedule',jsonb_build_object('order',p_order,'day',p_day,'vol',p_vol)); end $$;
create or replace function register_dispatch(p_item uuid,p_qty int,p_key text) returns void language plpgsql security definer set search_path=public as $$
declare it order_items; done int; stock int; begin
 if not has_role('{administrador,despacho}') then raise exception 'Sin permiso'; end if;
 select * into it from order_items where id=p_item for update;
 select coalesce(sum(qty),0) into done from dispatches where item_id=p_item;
 if done+p_qty>it.qty then raise exception 'Supera lo solicitado (saldo %)',it.qty-done; end if;
 select physical into stock from inventory where product_id=it.product_id for update;
 if stock<p_qty then raise exception 'Stock insuficiente (%)',stock; end if;
 insert into dispatches(item_id,qty,idem_key) values(p_item,p_qty,p_key);
 update inventory set physical=physical-p_qty where product_id=it.product_id;
 insert into audit(action,detail) values('dispatch',jsonb_build_object('item',p_item,'qty',p_qty)); end $$;
create or replace function stock_in(p_product uuid,p_qty int) returns void language plpgsql security definer set search_path=public as $$ begin
 if not has_role('{administrador,almacen}') then raise exception 'Sin permiso'; end if;
 update inventory set physical=physical+p_qty where product_id=p_product;
 insert into audit(action,detail) values('stock_in',jsonb_build_object('product',p_product,'qty',p_qty)); end $$;
create or replace view day_usage as select day, sum(volume) used, 120-sum(volume) free from schedule where status='pendiente' group by day;

alter table profiles enable row level security; alter table clients enable row level security; alter table products enable row level security; alter table inventory enable row level security;
alter table orders enable row level security; alter table order_items enable row level security; alter table schedule enable row level security; alter table dispatches enable row level security; alter table payments enable row level security; alter table audit enable row level security;
create policy p_sel on profiles for select using(id=auth.uid() or has_role('{administrador}'));
create policy p_upd on profiles for update using(has_role('{administrador}')) with check(has_role('{administrador}'));
create policy c_sel on clients for select using(is_staff()); create policy c_w on clients for all using(has_role('{administrador,ventas}')) with check(has_role('{administrador,ventas}'));
create policy pr_sel on products for select using(is_staff()); create policy pr_w on products for all using(has_role('{administrador}')) with check(has_role('{administrador}'));
create policy i_sel on inventory for select using(is_staff());
create policy o_sel on orders for select using(is_staff()); create policy o_w on orders for all using(has_role('{administrador,ventas}')) with check(has_role('{administrador,ventas}'));
create policy oi_sel on order_items for select using(is_staff()); create policy oi_w on order_items for all using(has_role('{administrador,ventas}')) with check(has_role('{administrador,ventas}'));
create policy s_sel on schedule for select using(is_staff());
create policy d_sel on dispatches for select using(is_staff());
create policy pay_sel on payments for select using(has_role('{administrador,contabilidad}')); create policy pay_w on payments for insert with check(has_role('{administrador,contabilidad}'));
create policy a_sel on audit for select using(has_role('{administrador}'));
grant select on day_usage to authenticated;
-- Ejecutar DESPUÉS de SQL_1 y SQL_2 (SQL Editor > Run)
create table delivery_notes(id uuid primary key default gen_random_uuid(), number bigint generated always as identity, dispatch_id uuid unique not null references dispatches, created_at timestamptz default now(), created_by uuid default auth.uid());
alter table delivery_notes enable row level security;
create policy dn_sel on delivery_notes for select using(is_staff());
create policy dn_ins on delivery_notes for insert with check(has_role('{administrador,despacho}'));
alter table payments add column if not exists idem_key text unique;
create or replace view order_balance with (security_invoker=true) as
select o.id order_id, o.number, c.name client,
 coalesce(t.total,0)+case when o.transport_charged then coalesce(o.transport,0) else 0 end+coalesce(o.extras,0) as total,
 coalesce(p.paid,0) as paid
from orders o join clients c on c.id=o.client_id
left join (select order_id,sum(amount) total from order_items group by 1) t on t.order_id=o.id
left join (select order_id,sum(amount) paid from payments group by 1) p on p.order_id=o.id;
grant select on order_balance to authenticated;
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
-- Ejecutar DESPUÉS de SQL_4 (SQL Editor > Run)
create table expenses(id uuid primary key default gen_random_uuid(), concept text not null, category text default 'general', amount numeric not null check(amount>0), method text default 'efectivo', idem_key text unique, created_by uuid default auth.uid(), created_at timestamptz default now());
create table cash_sessions(id uuid primary key default gen_random_uuid(), day date unique not null, opening numeric not null default 0, opened_by uuid default auth.uid(), closed boolean not null default false, expected numeric, counted numeric, difference numeric, closed_by uuid, closed_at timestamptz);
create or replace function lp_today() returns date language sql stable as $$ select (now() at time zone 'America/La_Paz')::date $$;
create or replace function cash_expected(p_day date) returns numeric language sql security definer stable set search_path=public as $$
 select coalesce((select opening from cash_sessions where day=p_day),0)
  + coalesce((select sum(amount) from payments where method='efectivo' and (created_at at time zone 'America/La_Paz')::date=p_day),0)
  - coalesce((select sum(amount) from expenses where method='efectivo' and (created_at at time zone 'America/La_Paz')::date=p_day),0) $$;
create or replace function open_cash(p_opening numeric) returns void language plpgsql security definer set search_path=public as $$ begin
 if not has_role('{administrador,contabilidad}') then raise exception 'Sin permiso'; end if;
 insert into cash_sessions(day,opening) values(lp_today(),p_opening); end $$;
create or replace function close_cash(p_counted numeric) returns void language plpgsql security definer set search_path=public as $$
declare e numeric; begin
 if not has_role('{administrador,contabilidad}') then raise exception 'Sin permiso'; end if;
 e:=cash_expected(lp_today());
 update cash_sessions set closed=true,expected=e,counted=p_counted,difference=p_counted-e,closed_by=auth.uid(),closed_at=now() where day=lp_today() and not closed;
 if not found then raise exception 'No hay caja abierta hoy'; end if;
 insert into audit(action,detail) values('cash_close',jsonb_build_object('expected',e,'counted',p_counted)); end $$;
create or replace function block_closed_cash() returns trigger language plpgsql security definer set search_path=public as $$ begin
 if new.method='efectivo' and exists(select 1 from cash_sessions where day=lp_today() and closed) then raise exception 'La caja de hoy ya está cerrada'; end if; return new; end $$;
create trigger t_pay_cash before insert on payments for each row execute function block_closed_cash();
create trigger t_exp_cash before insert on expenses for each row execute function block_closed_cash();
alter table expenses enable row level security; alter table cash_sessions enable row level security;
create policy ex_sel on expenses for select using(has_role('{administrador,contabilidad}')); create policy ex_w on expenses for insert with check(has_role('{administrador,contabilidad}'));
create policy cs_sel on cash_sessions for select using(has_role('{administrador,contabilidad}'));

create table accounts(id uuid primary key default gen_random_uuid(), code text unique not null, name text not null, type text not null, parent_id uuid references accounts, active boolean default true);
create table journal_entries(id uuid primary key default gen_random_uuid(), number bigint generated always as identity, day date not null, description text not null, ref text, created_by uuid default auth.uid(), created_at timestamptz default now());
create table journal_lines(id uuid primary key default gen_random_uuid(), entry_id uuid not null references journal_entries, account_id uuid not null references accounts, debit numeric not null default 0 check(debit>=0), credit numeric not null default 0 check(credit>=0), check(debit=0 or credit=0));
create or replace function post_entry(p_day date,p_desc text,p_ref text,p_lines jsonb) returns void language plpgsql security definer set search_path=public as $$
declare d numeric; c numeric; eid uuid; l jsonb; begin
 if not has_role('{administrador,contabilidad}') then raise exception 'Sin permiso'; end if;
 select coalesce(sum((x->>'debit')::numeric),0),coalesce(sum((x->>'credit')::numeric),0) into d,c from jsonb_array_elements(p_lines) x;
 if d<>c or d=0 then raise exception 'Asiento descuadrado: debe % / haber %',d,c; end if;
 insert into journal_entries(day,description,ref) values(p_day,p_desc,p_ref) returning id into eid;
 for l in select * from jsonb_array_elements(p_lines) loop
  insert into journal_lines(entry_id,account_id,debit,credit) values(eid,(l->>'account')::uuid,(l->>'debit')::numeric,(l->>'credit')::numeric); end loop; end $$;
create or replace function reverse_entry(p_id uuid) returns void language plpgsql security definer set search_path=public as $$
declare e journal_entries; eid uuid; begin
 if not has_role('{administrador,contabilidad}') then raise exception 'Sin permiso'; end if;
 select * into e from journal_entries where id=p_id;
 if exists(select 1 from journal_entries where ref='ANULA #'||e.number) then raise exception 'Asiento ya anulado'; end if;
 insert into journal_entries(day,description,ref) values(lp_today(),'Anulación: '||e.description,'ANULA #'||e.number) returning id into eid;
 insert into journal_lines(entry_id,account_id,debit,credit) select eid,account_id,credit,debit from journal_lines where entry_id=p_id; end $$;
alter table accounts enable row level security; alter table journal_entries enable row level security; alter table journal_lines enable row level security;
create policy ac_sel on accounts for select using(has_role('{administrador,contabilidad}')); create policy ac_w on accounts for insert with check(has_role('{administrador,contabilidad}'));
create policy je_sel on journal_entries for select using(has_role('{administrador,contabilidad}'));
create policy jl_sel on journal_lines for select using(has_role('{administrador,contabilidad}'));
create or replace view account_balances with (security_invoker=true) as
select a.id,a.code,a.name,a.type,coalesce(sum(l.debit),0) debit,coalesce(sum(l.credit),0) credit from accounts a left join journal_lines l on l.account_id=a.id group by a.id order by a.code;
grant select on account_balances to authenticated;
insert into accounts(code,name,type) values('1.1','Caja','activo'),('1.2','Cuentas por cobrar','activo'),('1.3','Inventarios','activo'),('2.1','Comisiones por pagar','pasivo'),('2.2','Proveedores','pasivo'),('3.1','Capital','patrimonio'),('4.1','Ventas','ingreso'),('5.1','Costo de ventas','costo'),('6.1','Transporte','gasto'),('6.2','Comisiones','gasto'),('6.3','Gastos generales','gasto');
-- Ejecutar DESPUÉS de SQL_5 (SQL Editor > Run)
create table company_settings(id int primary key default 1 check(id=1), name text default 'PLASTOFORMO EPS', info text default 'Dirección / Teléfono');
insert into company_settings default values;
create table price_lists(id uuid primary key default gen_random_uuid(), name text not null);
create table price_list_items(id uuid primary key default gen_random_uuid(), list_id uuid not null references price_lists on delete cascade, product_id uuid not null references products, price_m3 numeric not null check(price_m3>=0), unique(list_id,product_id));
alter table clients add column if not exists price_list_id uuid references price_lists;
create table quotes(id uuid primary key default gen_random_uuid(), number bigint generated always as identity, client_id uuid not null references clients, status text not null default 'abierta', created_by uuid default auth.uid(), created_at timestamptz default now());
create table quote_items(id uuid primary key default gen_random_uuid(), quote_id uuid not null references quotes on delete cascade, product_id uuid not null references products, qty int not null check(qty>0));
create table stock_adjustments(id uuid primary key default gen_random_uuid(), product_id uuid not null references products, delta int not null, reason text not null, created_by uuid default auth.uid(), created_at timestamptz default now());
alter table company_settings enable row level security; alter table price_lists enable row level security; alter table price_list_items enable row level security; alter table quotes enable row level security; alter table quote_items enable row level security; alter table stock_adjustments enable row level security;
create policy cset_sel on company_settings for select using(is_staff()); create policy cset_upd on company_settings for update using(has_role('{administrador}')) with check(has_role('{administrador}'));
create policy pl_sel on price_lists for select using(is_staff()); create policy pl_w on price_lists for insert with check(has_role('{administrador}'));
create policy pli_sel on price_list_items for select using(is_staff()); create policy pli_w on price_list_items for all using(has_role('{administrador}')) with check(has_role('{administrador}'));
create policy q_sel on quotes for select using(is_staff()); create policy q_w on quotes for insert with check(has_role('{administrador,ventas}'));
create policy qi_sel on quote_items for select using(is_staff()); create policy qi_w on quote_items for insert with check(has_role('{administrador,ventas}'));
create policy sa_sel on stock_adjustments for select using(has_role('{administrador,almacen}'));
create or replace function snap_item() returns trigger language plpgsql as $$ begin
 select volume_piece into new.volume_piece from products where id=new.product_id;
 select coalesce((select pli.price_m3 from price_list_items pli join clients c on c.price_list_id=pli.list_id join orders o on o.client_id=c.id where o.id=new.order_id and pli.product_id=new.product_id),(select price_m3 from products where id=new.product_id)) into new.price_m3; return new; end $$;
create or replace function convert_quote(p_id uuid) returns void language plpgsql security definer set search_path=public as $$
declare q quotes; oid uuid; begin
 if not has_role('{administrador,ventas}') then raise exception 'Sin permiso'; end if;
 select * into q from quotes where id=p_id for update;
 if q.status<>'abierta' then raise exception 'Cotización ya convertida'; end if;
 insert into orders(client_id) values(q.client_id) returning id into oid;
 insert into order_items(order_id,product_id,qty) select oid,product_id,qty from quote_items where quote_id=p_id;
 update quotes set status='convertida' where id=p_id; end $$;
create or replace function adjust_stock(p_product uuid,p_delta int,p_reason text) returns void language plpgsql security definer set search_path=public as $$ begin
 if not has_role('{administrador,almacen}') then raise exception 'Sin permiso'; end if;
 if coalesce(trim(p_reason),'')='' then raise exception 'Motivo obligatorio'; end if;
 update inventory set physical=physical+p_delta where product_id=p_product;
 insert into stock_adjustments(product_id,delta,reason) values(p_product,p_delta,p_reason);
 insert into audit(action,detail) values('stock_adjust',jsonb_build_object('product',p_product,'delta',p_delta,'reason',p_reason)); end $$;
create or replace function auto_entry(p_desc text,p_ref text,p_dr text,p_cr text,p_amt numeric) returns void language plpgsql security definer set search_path=public as $$ declare eid uuid; begin
 if coalesce(p_amt,0)<=0 then return; end if;
 insert into journal_entries(day,description,ref) values(lp_today(),p_desc,p_ref) returning id into eid;
 insert into journal_lines(entry_id,account_id,debit,credit) select eid,id,p_amt,0 from accounts where code=p_dr;
 insert into journal_lines(entry_id,account_id,debit,credit) select eid,id,0,p_amt from accounts where code=p_cr; end $$;
create or replace function tg_pay() returns trigger language plpgsql security definer set search_path=public as $$ begin perform auto_entry('Cobro de pedido','AUTO-PAGO '||new.id,'1.1','1.2',new.amount); return new; end $$;
create or replace function tg_exp() returns trigger language plpgsql security definer set search_path=public as $$ begin perform auto_entry('Gasto: '||new.concept,'AUTO-GASTO '||new.id,'6.3','1.1',new.amount); return new; end $$;
create or replace function tg_disp() returns trigger language plpgsql security definer set search_path=public as $$ declare v numeric; p numeric; begin
 select volume_piece,price_m3 into v,p from order_items where id=new.item_id;
 perform auto_entry('Venta por despacho','AUTO-VENTA '||new.id,'1.2','4.1',new.qty*v*p);
 perform auto_entry('Costo de venta por despacho','AUTO-COSTO '||new.id,'5.1','1.3',new.qty*v*new.cost_m3); return new; end $$;
create or replace function tg_purch() returns trigger language plpgsql security definer set search_path=public as $$ declare a numeric; begin
 if new.status='recibida' and old.status='borrador' then
  select sum(i.qty*p.volume_piece*i.cost_m3) into a from purchase_items i join products p on p.id=i.product_id where i.purchase_id=new.id;
  perform auto_entry('Compra #'||new.number,'AUTO-COMPRA '||new.id,'1.3','2.2',a); end if; return new; end $$;
create trigger a_pay after insert on payments for each row execute function tg_pay();
create trigger a_exp after insert on expenses for each row execute function tg_exp();
create trigger a_disp after insert on dispatches for each row execute function tg_disp();
create trigger a_purch after update on purchases for each row execute function tg_purch();
create or replace view client_sales with (security_invoker=true) as select c.name, count(distinct o.id) pedidos, sum(i.amount) importe, sum(i.qty*i.volume_piece) m3 from clients c join orders o on o.client_id=c.id join order_items i on i.order_id=o.id group by c.id;
create or replace view product_sales with (security_invoker=true) as select p.code,p.espesor,p.largo,p.ancho, sum(i.qty) piezas, sum(i.qty*i.volume_piece) m3, sum(i.amount) importe from products p join order_items i on i.product_id=p.id group by p.id;
grant select on client_sales, product_sales to authenticated;
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
-- Ejecutar DESPUÉS de SQL_7 (SQL Editor > Run)
-- Opcional, para iniciar la numeración en otro número: alter table orders alter column number restart with 1000;
alter table orders add column if not exists due_date date;
create or replace view order_balance with (security_invoker=true) as
select o.id order_id, o.number, c.name client,
 case when o.status='anulado' then 0 else coalesce(t.total,0)*(1-coalesce(o.discount_pct,0)/100)+case when o.transport_charged then coalesce(o.transport,0) else 0 end+coalesce(o.extras,0) end as total,
 coalesce(p.paid,0) as paid, o.due_date, o.status
from orders o join clients c on c.id=o.client_id
left join (select order_id,sum(amount) total from order_items group by 1) t on t.order_id=o.id
left join (select order_id,sum(amount) paid from payments group by 1) p on p.order_id=o.id;
create or replace view client_sales with (security_invoker=true) as select c.name, count(distinct o.id) pedidos, sum(i.amount) importe, sum(i.qty*i.volume_piece) m3 from clients c join orders o on o.client_id=c.id join order_items i on i.order_id=o.id where o.status<>'anulado' group by c.id;
create or replace view product_sales with (security_invoker=true) as select p.code,p.espesor,p.largo,p.ancho, sum(i.qty) piezas, sum(i.qty*i.volume_piece) m3, sum(i.amount) importe from products p join order_items i on i.product_id=p.id join orders o on o.id=i.order_id where o.status<>'anulado' group by p.id;
create or replace view daily_sales with (security_invoker=true) as
select (o.created_at at time zone 'America/La_Paz')::date as day, count(*) pedidos, sum(b.total) importe, sum(coalesce(v.m3,0)) m3
from orders o join order_balance b on b.order_id=o.id left join (select order_id,sum(qty*volume_piece) m3 from order_items group by 1) v on v.order_id=o.id
where o.status<>'anulado' group by 1;
grant select on client_sales, product_sales, daily_sales to authenticated;
create or replace function cancel_order(p_id uuid,p_reason text) returns void language plpgsql security definer set search_path=public as $$ begin
 if not has_role('{administrador,ventas}') then raise exception 'Sin permiso'; end if;
 if coalesce(trim(p_reason),'')='' then raise exception 'Motivo obligatorio'; end if;
 if exists(select 1 from dispatches d join order_items i on i.id=d.item_id where i.order_id=p_id) then raise exception 'El pedido ya tiene despachos'; end if;
 if exists(select 1 from payments where order_id=p_id) then raise exception 'El pedido tiene pagos registrados'; end if;
 update orders set status='anulado' where id=p_id and status<>'anulado';
 update schedule set status='cancelado' where order_id=p_id and status='pendiente';
 insert into audit(action,detail) values('order_cancel',jsonb_build_object('order',p_id,'reason',p_reason)); end $$;
create or replace function block_annulled_disp() returns trigger language plpgsql security definer set search_path=public as $$ begin
 if exists(select 1 from order_items i join orders o on o.id=i.order_id where i.id=new.item_id and o.status='anulado') then raise exception 'El pedido está anulado'; end if; return new; end $$;
create trigger t_disp_ann before insert on dispatches for each row execute function block_annulled_disp();
create or replace function block_annulled_pay() returns trigger language plpgsql security definer set search_path=public as $$ begin
 if exists(select 1 from orders where id=new.order_id and status='anulado') then raise exception 'El pedido está anulado'; end if; return new; end $$;
create trigger t_pay_ann before insert on payments for each row execute function block_annulled_pay();
