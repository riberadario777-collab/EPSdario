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
