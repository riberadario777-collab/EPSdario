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
