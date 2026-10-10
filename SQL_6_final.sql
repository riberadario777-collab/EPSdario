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
