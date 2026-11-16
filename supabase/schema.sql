-- =====================================================================
-- ApeSync — banco de dados (Supabase / PostgreSQL)
-- Rode este arquivo inteiro no Supabase: Dashboard → SQL Editor → New query.
-- Pode rodar de novo sem problema (é idempotente).
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1) Tabelas
-- Todas usam UUID gerado NO CELULAR (permite criar registros offline),
-- exclusão lógica (deleted) para a exclusão também sincronizar, e duas
-- marcas de tempo:
--   updated_at  -> quando o usuário alterou (relógio do celular; decide conflitos)
--   synced_at   -> quando o servidor recebeu (relógio do servidor; usado no "pull")
-- ---------------------------------------------------------------------

create table if not exists public.casas (
  id             uuid primary key,
  nome           text not null check (char_length(nome) between 1 and 60),
  codigo_convite text not null unique check (char_length(codigo_convite) = 6),
  criado_por     uuid not null references auth.users (id),
  updated_at     timestamptz not null default now(),
  deleted        boolean not null default false,
  synced_at      timestamptz not null default now()
);

create table if not exists public.moradores (
  id          uuid primary key,
  casa_id     uuid not null references public.casas (id),
  nome        text not null check (char_length(nome) between 1 and 40),
  cor         smallint not null default 0,
  usuario_id  uuid references auth.users (id),  -- null = morador sem conta no app
  updated_at  timestamptz not null default now(),
  deleted     boolean not null default false,
  synced_at   timestamptz not null default now()
);
create index if not exists moradores_casa_idx on public.moradores (casa_id, synced_at);
create index if not exists moradores_usuario_idx on public.moradores (usuario_id);

create table if not exists public.gastos (
  id              uuid primary key,
  casa_id         uuid not null references public.casas (id),
  descricao       text not null check (char_length(descricao) between 1 and 80),
  valor_centavos  integer not null check (valor_centavos > 0),
  categoria       text not null check (categoria in ('mercado','contas','moradia','outros')),
  pago_por        uuid not null references public.moradores (id),
  dividido_entre  uuid[] not null check (cardinality(dividido_entre) > 0),
  data            date not null,
  criado_por      uuid references auth.users (id),
  updated_at      timestamptz not null default now(),
  deleted         boolean not null default false,
  synced_at       timestamptz not null default now()
);
create index if not exists gastos_casa_idx on public.gastos (casa_id, synced_at);

create table if not exists public.pagamentos (
  id              uuid primary key,
  casa_id         uuid not null references public.casas (id),
  de_id           uuid not null references public.moradores (id),
  para_id         uuid not null references public.moradores (id),
  valor_centavos  integer not null check (valor_centavos > 0),
  data            date not null,
  updated_at      timestamptz not null default now(),
  deleted         boolean not null default false,
  synced_at       timestamptz not null default now(),
  check (de_id <> para_id)
);
create index if not exists pagamentos_casa_idx on public.pagamentos (casa_id, synced_at);

-- ---------------------------------------------------------------------
-- 2) synced_at é sempre o relógio do SERVIDOR (o app nunca escolhe)
-- ---------------------------------------------------------------------
create or replace function public.marcar_synced_at()
returns trigger language plpgsql as $$
begin
  new.synced_at := clock_timestamp();
  return new;
end $$;

do $$
declare t text;
begin
  foreach t in array array['casas','moradores','gastos','pagamentos'] loop
    execute format('drop trigger if exists trg_synced_at on public.%I', t);
    execute format(
      'create trigger trg_synced_at before insert or update on public.%I
         for each row execute function public.marcar_synced_at()', t);
  end loop;
end $$;

-- ---------------------------------------------------------------------
-- 3) Segurança (Row Level Security): cada usuário só vê e altera
--    os dados das casas em que ele é morador.
-- ---------------------------------------------------------------------
create or replace function public.eh_membro(p_casa uuid)
returns boolean language sql security definer stable set search_path = public as $$
  select exists (
    select 1 from public.moradores
     where casa_id = p_casa and usuario_id = auth.uid() and not deleted
  ) or exists (
    select 1 from public.casas where id = p_casa and criado_por = auth.uid()
  );
$$;

alter table public.casas      enable row level security;
alter table public.moradores  enable row level security;
alter table public.gastos     enable row level security;
alter table public.pagamentos enable row level security;

drop policy if exists casas_select on public.casas;
drop policy if exists casas_insert on public.casas;
drop policy if exists casas_update on public.casas;
-- (criado_por = auth.uid() é checado direto na linha: no upsert da casa
--  recém-criada offline, ela ainda não existe na tabela)
create policy casas_select on public.casas for select using (criado_por = auth.uid() or public.eh_membro(id));
create policy casas_insert on public.casas for insert with check (criado_por = auth.uid());
create policy casas_update on public.casas for update using (criado_por = auth.uid() or public.eh_membro(id));

do $$
declare t text;
begin
  foreach t in array array['moradores','gastos','pagamentos'] loop
    execute format('drop policy if exists %I on public.%I', t || '_select', t);
    execute format('drop policy if exists %I on public.%I', t || '_insert', t);
    execute format('drop policy if exists %I on public.%I', t || '_update', t);
    execute format('create policy %I on public.%I for select using (public.eh_membro(casa_id))', t || '_select', t);
    execute format('create policy %I on public.%I for insert with check (public.eh_membro(casa_id))', t || '_insert', t);
    execute format('create policy %I on public.%I for update using (public.eh_membro(casa_id))', t || '_update', t);
  end loop;
end $$;
-- Não existe policy de DELETE: exclusão é sempre lógica (deleted = true).

-- ---------------------------------------------------------------------
-- 4) Entrar numa casa pelo código de convite (precisa de internet).
--    security definer: o usuário ainda não é membro, então não enxergaria
--    a casa pelas policies acima.
-- ---------------------------------------------------------------------
create or replace function public.entrar_na_casa(p_codigo text, p_nome text)
returns uuid language plpgsql security definer set search_path = public as $$
declare
  v_casa uuid;
  v_cor  smallint;
begin
  if auth.uid() is null then
    raise exception 'Faça login primeiro';
  end if;

  select id into v_casa from public.casas
   where codigo_convite = upper(trim(p_codigo)) and not deleted;
  if v_casa is null then
    raise exception 'Código de convite inválido';
  end if;

  if not exists (select 1 from public.moradores
                  where casa_id = v_casa and usuario_id = auth.uid() and not deleted) then
    select count(*) % 8 into v_cor from public.moradores where casa_id = v_casa;
    insert into public.moradores (id, casa_id, nome, cor, usuario_id)
    values (gen_random_uuid(), v_casa, left(coalesce(nullif(trim(p_nome), ''), 'Morador'), 40), v_cor, auth.uid());
  end if;

  return v_casa;
end $$;

grant execute on function public.entrar_na_casa(text, text) to authenticated;
grant execute on function public.eh_membro(uuid) to authenticated;

-- ---------------------------------------------------------------------
-- 5) Realtime: o app recebe aviso na hora quando outro morador muda algo
-- ---------------------------------------------------------------------
do $$
declare t text;
begin
  foreach t in array array['casas','moradores','gastos','pagamentos'] loop
    if not exists (select 1 from pg_publication_tables
                    where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = t) then
      execute format('alter publication supabase_realtime add table public.%I', t);
    end if;
  end loop;
end $$;
