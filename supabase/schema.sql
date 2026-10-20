-- Execute no SQL Editor do Supabase, uma vez.
create extension if not exists btree_gist;
create table if not exists public.admins (
  user_id uuid primary key references auth.users(id) on delete cascade
);
create table if not exists public.services (
  id uuid primary key default gen_random_uuid(),
  name text not null check (length(trim(name)) between 2 and 80),
  description text default '',
  price numeric(10,2) not null check(price>=0),
  duration_minutes integer not null check(duration_minutes in (30,60,90,120,150,180)),
  sort_order integer not null default 0,
  active boolean not null default true
);
create table if not exists public.shop_settings (
  id integer primary key default 1 check(id=1),
  weekly_hours jsonb not null default '{"0":[],"1":[["09:00","12:00"],["13:00","18:00"]],"2":[["09:00","12:00"],["13:00","18:00"]],"3":[["09:00","12:00"],["13:00","18:00"]],"4":[["09:00","12:00"],["13:00","18:00"]],"5":[["09:00","12:00"],["13:00","18:00"]],"6":[["09:00","13:00"]]}'::jsonb
);
create table if not exists public.bookings (
  id uuid primary key default gen_random_uuid(),
  service_id uuid not null references public.services(id),
  customer_name text not null check(length(trim(customer_name)) between 2 and 100),
  customer_phone text not null check(customer_phone ~ '^[0-9]{10,13}$'),
  booking_date date not null,
  start_time time not null,
  end_time time not null,
  status text not null default 'scheduled' check(status in ('scheduled','completed','cancelled')),
  created_at timestamptz not null default now(),
  constraint positive_booking_time check(end_time>start_time),
  constraint no_booking_overlap exclude using gist (
    booking_date with =,
    tsrange(('2000-01-01'::date + start_time),('2000-01-01'::date + end_time),'[)') with &&
  ) where (status <> 'cancelled')
);
create index if not exists bookings_date_idx on public.bookings(booking_date);
insert into public.shop_settings(id) values(1) on conflict(id) do nothing;
insert into public.services(name,description,price,duration_minutes,sort_order) select * from (values
('Corte masculino','Corte com acabamento e estilo.',35.00::numeric,30,1),
('Barba','Barba desenhada e finalização.',25.00::numeric,30,2),
('Corte + barba','Combo completo para renovar o visual.',55.00::numeric,60,3)) as v(name,description,price,duration_minutes,sort_order)
where not exists(select 1 from public.services);
create or replace function public.is_admin() returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.admins where user_id=(select auth.uid()));
$$;
revoke all on function public.is_admin() from public;
grant execute on function public.is_admin() to authenticated;
alter table public.admins enable row level security;
alter table public.services enable row level security;
alter table public.shop_settings enable row level security;
alter table public.bookings enable row level security;
drop policy if exists "read active services" on public.services;
create policy "read active services" on public.services for select to anon,authenticated using(active or public.is_admin());
drop policy if exists "admin services" on public.services;
create policy "admin services" on public.services for all to authenticated using(public.is_admin()) with check(public.is_admin());
drop policy if exists "read settings" on public.shop_settings;
create policy "read settings" on public.shop_settings for select to anon,authenticated using(true);
drop policy if exists "admin settings" on public.shop_settings;
create policy "admin settings" on public.shop_settings for all to authenticated using(public.is_admin()) with check(public.is_admin());
drop policy if exists "admin bookings" on public.bookings;
create policy "admin bookings" on public.bookings for all to authenticated using(public.is_admin()) with check(public.is_admin());
-- Não conceder SELECT público a bookings: contém dados pessoais.
create or replace function public.public_busy_intervals(p_date date)
returns table(start_time time,end_time time) language sql stable security definer set search_path='' as $$
 select b.start_time,b.end_time from public.bookings b where b.booking_date=p_date and b.status <> 'cancelled';
$$;
create or replace function public.create_public_booking(
 p_service_id uuid,p_date date,p_start_time time,p_customer_name text,p_customer_phone text
) returns uuid language plpgsql security definer set search_path='' as $$
declare v_service public.services%rowtype;v_end time;v_day int;v_period jsonb;v_start time;v_finish time;v_valid boolean:=false;v_id uuid;
begin
 if p_date < (now() at time zone 'America/Fortaleza')::date or p_date > (now() at time zone 'America/Fortaleza')::date + 90 then raise exception 'Data fora do período permitido';end if;
 if length(trim(p_customer_name)) not between 2 and 100 or p_customer_phone !~ '^[0-9]{10,13}$' then raise exception 'Dados do cliente inválidos';end if;
 if extract(minute from p_start_time)::int not in (0,30) or extract(second from p_start_time)::int<>0 then raise exception 'Horário inválido';end if;
 if (p_date + p_start_time) <= (now() at time zone 'America/Fortaleza') then raise exception 'Escolha um horário futuro';end if;
 select * into v_service from public.services where id=p_service_id and active=true;
 if not found then raise exception 'Serviço indisponível';end if;
 v_end:=p_start_time + make_interval(mins=>v_service.duration_minutes);
 if v_end<=p_start_time then raise exception 'Horário inválido';end if;
 v_day:=extract(dow from p_date)::int;
 for v_period in select value from jsonb_array_elements((select weekly_hours->(v_day::text) from public.shop_settings where id=1)) loop
   v_start:=(v_period->>0)::time;v_finish:=(v_period->>1)::time;
   if p_start_time>=v_start and v_end<=v_finish then v_valid:=true;exit;end if;
 end loop;
 if not v_valid then raise exception 'Fora do horário de atendimento';end if;
 insert into public.bookings(service_id,customer_name,customer_phone,booking_date,start_time,end_time)
 values(p_service_id,trim(p_customer_name),p_customer_phone,p_date,p_start_time,v_end) returning id into v_id;
 return v_id;
exception when exclusion_violation then raise exception 'Este horário acabou de ser reservado. Escolha outro.';
end;
$$;
revoke all on function public.public_busy_intervals(date) from public;
revoke all on function public.create_public_booking(uuid,date,time,text,text) from public;
grant execute on function public.public_busy_intervals(date) to anon,authenticated;
grant execute on function public.create_public_booking(uuid,date,time,text,text) to anon,authenticated;
-- Após criar o usuário em Authentication > Users, execute substituindo o e-mail:
-- insert into public.admins(user_id) select id from auth.users where email='EMAIL_DO_ROSSY';
