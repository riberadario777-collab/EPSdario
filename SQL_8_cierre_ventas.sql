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
