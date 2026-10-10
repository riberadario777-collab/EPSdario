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
