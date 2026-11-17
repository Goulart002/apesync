-- =====================================================================
-- ApeSync — banco de dados (Supabase / PostgreSQL)
-- Rode este arquivo inteiro no Supabase: Dashboard → SQL Editor → New query.
-- Pode rodar de novo sem problema (é idempotente) — inclusive por cima de
-- um banco que já tem dados: nada é apagado.
-- =====================================================================

-- --------------------------------------------------------------------
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
  admin_id       uuid references auth.users (id),  -- quem administra a casa
  updated_at     timestamptz not null default now(),
  deleted        boolean not null default false,
  synced_at      timestamptz not null default now()
);

-- Bancos antigos (antes do administrador): cria a coluna e define quem
-- criou a casa como administrador.
alter table public.casas add column if not exists admin_id uuid references auth.users (id);
update public.casas set admin_id = criado_por where admin_id is null;
alter table public.casas alter column admin_id set not null;

create table if not exists public.moradores (
  id          uuid primary key,
  casa_id     uuid not null references public.casas (id),
  nome        text not null check (char_length(nome) between 1 and 40),
  cor         smallint not null default 0,
  usuario_id  uuid references auth.users (id),  -- null só em cadastros antigos
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
  categoria       text not null,
  pago_por        uuid not null references public.moradores (id),
  dividido_entre  uuid[] not null check (cardinality(dividido_entre) > 0),
  data            date not null,
  criado_por      uuid references auth.users (id),
  updated_at      timestamptz not null default now(),
  deleted         boolean not null default false,
  synced_at       timestamptz not null default now()
);
create index if not exists gastos_casa_idx on public.gastos (casa_id, synced_at);

-- Categorias válidas. 'ajuste' é criada pelo app quando o admin remove um
-- morador que estava devendo (a dívida é dividida entre quem fica).
alter table public.gastos drop constraint if exists gastos_categoria_check;
alter table public.gastos add constraint gastos_categoria_check
  check (categoria in ('mercado','contas','moradia','outros','ajuste'));

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
-- 2) Triggers
-- ---------------------------------------------------------------------

-- synced_at é sempre o relógio do SERVIDOR (o app nunca escolhe)
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

-- Casa nova sem admin_id (versões antigas do app): quem criou é o admin.
create or replace function public.casa_admin_padrao()
returns trigger language plpgsql as $$
begin
  if new.admin_id is null then
    new.admin_id := new.criado_por;
  end if;
  return new;
end $$;

drop trigger if exists trg_casa_admin on public.casas;
create trigger trg_casa_admin before insert on public.casas
  for each row execute function public.casa_admin_padrao();

-- Morador: não pode trocar de casa nem de dono (usuario_id), e o
-- administrador não pode sair sem antes transferir a administração.
create or replace function public.proteger_morador()
returns trigger language plpgsql as $$
begin
  new.casa_id := old.casa_id;
  new.usuario_id := old.usuario_id;
  if new.deleted and not old.deleted and old.usuario_id is not null and exists (
       select 1 from public.casas c
        where c.id = old.casa_id and c.admin_id = old.usuario_id) then
    raise exception 'Transfira a administração para outro morador antes de sair da casa';
  end if;
  return new;
end $$;

drop trigger if exists trg_proteger_morador on public.moradores;
create trigger trg_proteger_morador before update on public.moradores
  for each row execute function public.proteger_morador();

-- Gasto: não muda de casa nem de autor (criado_por) depois de criado.
create or replace function public.proteger_gasto()
returns trigger language plpgsql as $$
begin
  new.casa_id := old.casa_id;
  new.criado_por := old.criado_por;
  return new;
end $$;

drop trigger if exists trg_proteger_gasto on public.gastos;
create trigger trg_proteger_gasto before update on public.gastos
  for each row execute function public.proteger_gasto();

-- Pagamento: não muda de casa depois de criado.
create or replace function public.proteger_pagamento()
returns trigger language plpgsql as $$
begin
  new.casa_id := old.casa_id;
  return new;
end $$;

drop trigger if exists trg_proteger_pagamento on public.pagamentos;
create trigger trg_proteger_pagamento before update on public.pagamentos
  for each row execute function public.proteger_pagamento();

-- "A alteração mais recente vence" (last write wins), decidido NO SERVIDOR.
-- Ex.: o celular A editou um gasto offline às 10h; o celular B editou o
-- mesmo gasto às 11h. Quando A volta a ter internet e envia a versão das
-- 10h, ela é ignorada e o servidor fica com a das 11h (que A baixa logo em
-- seguida). Sem isso, quem enviasse por último apagaria a edição mais nova.
-- Também impede que um celular com o relógio adiantado vença sempre.
-- (O nome começa com "trg_0" para rodar antes dos outros triggers.)
create or replace function public.mais_recente_vence()
returns trigger language plpgsql as $$
begin
  if new.updated_at > now() + interval '5 minutes' then
    new.updated_at := now();
  end if;
  if tg_op = 'UPDATE' and new.updated_at < old.updated_at then
    return null;  -- versão mais velha que a do servidor: ignora em silêncio
  end if;
  return new;
end $$;

do $$
declare t text;
begin
  foreach t in array array['casas','moradores','gastos','pagamentos'] loop
    execute format('drop trigger if exists trg_0_mais_recente on public.%I', t);
    execute format(
      'create trigger trg_0_mais_recente before insert or update on public.%I
         for each row execute function public.mais_recente_vence()', t);
  end loop;
end $$;

-- Quem pagou, quem divide e quem paga/recebe precisam ser moradores DESTA
-- casa (atuais ou antigos: gastos antigos e ajustes citam quem já saiu).
create or replace function public.validar_moradores_gasto()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if not exists (select 1 from public.moradores
                  where id = new.pago_por and casa_id = new.casa_id) then
    raise exception 'Quem pagou não é morador desta casa';
  end if;
  if exists (select 1 from unnest(new.dividido_entre) as d(id)
              where not exists (select 1 from public.moradores m
                                 where m.id = d.id and m.casa_id = new.casa_id)) then
    raise exception 'A divisão inclui alguém que não é morador desta casa';
  end if;
  return new;
end $$;

drop trigger if exists trg_validar_moradores on public.gastos;
create trigger trg_validar_moradores before insert or update on public.gastos
  for each row execute function public.validar_moradores_gasto();

create or replace function public.validar_moradores_pagamento()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if (select count(*) from public.moradores
       where id in (new.de_id, new.para_id) and casa_id = new.casa_id) < 2 then
    raise exception 'Quem paga e quem recebe precisam ser moradores desta casa';
  end if;
  return new;
end $$;

drop trigger if exists trg_validar_moradores on public.pagamentos;
create trigger trg_validar_moradores before insert or update on public.pagamentos
  for each row execute function public.validar_moradores_pagamento();

-- ---------------------------------------------------------------------
-- 3) Segurança (Row Level Security)
--
--   Todo morador:   vê os dados da casa, lança gastos, edita o próprio nome,
--                   edita/exclui os gastos que ELE lançou, registra
--                   pagamentos em que ele é quem paga ou quem recebe,
--                   e pode sair da casa.
--   Administrador:  tudo isso + remove moradores, edita qualquer gasto ou
--                   pagamento, renomeia a casa, gera novo código de convite
--                   e transfere a administração.
--   Novos moradores só entram pelo código de convite (função entrar_na_casa).
-- ---------------------------------------------------------------------

-- Funções auxiliares (security definer: leem as tabelas sem passar pelas
-- policies, senão as policies ficariam chamando a si mesmas).
create or replace function public.eh_membro(p_casa uuid)
returns boolean language sql security definer stable set search_path = public as $$
  select exists (
    select 1 from public.moradores
     where casa_id = p_casa and usuario_id = auth.uid() and not deleted
  ) or exists (
    select 1 from public.casas where id = p_casa and admin_id = auth.uid()
  );
$$;

create or replace function public.eh_admin(p_casa uuid)
returns boolean language sql security definer stable set search_path = public as $$
  select exists (
    select 1 from public.casas where id = p_casa and admin_id = auth.uid()
  );
$$;

-- O morador p_morador é o usuário logado?
create or replace function public.eh_meu_morador(p_morador uuid)
returns boolean language sql security definer stable set search_path = public as $$
  select exists (
    select 1 from public.moradores
     where id = p_morador and usuario_id = auth.uid() and not deleted
  );
$$;

alter table public.casas      enable row level security;
alter table public.moradores  enable row level security;
alter table public.gastos     enable row level security;
alter table public.pagamentos enable row level security;

-- Apaga as policies antigas (versão sem administrador) e as atuais,
-- para recriar logo abaixo.
do $$
declare t text; op text;
begin
  foreach t in array array['casas','moradores','gastos','pagamentos'] loop
    foreach op in array array['select','insert','update','delete'] loop
      execute format('drop policy if exists %I on public.%I', t || '_' || op, t);
    end loop;
  end loop;
end $$;

-- Atenção: o app sincroniza com UPSERT (insert ... on conflict do update),
-- e no upsert o Postgres pode checar a regra de INSERT mesmo quando a linha
-- já existe. Por isso as regras de insert abaixo também aceitam as edições
-- legítimas (ex.: o admin editando o gasto de outra pessoa).

-- Casas
-- (admin_id = auth.uid() é checado direto na linha: no upsert da casa
--  recém-criada offline, ela ainda não existe na tabela)
create policy casas_select on public.casas for select
  using (admin_id = auth.uid() or public.eh_membro(id));
create policy casas_insert on public.casas for insert
  with check (admin_id = auth.uid() or (admin_id is null and criado_por = auth.uid()));
-- Só o admin altera a casa, e não consegue "dar" a casa para outra pessoa
-- por aqui (isso é feito pela função transferir_admin).
create policy casas_update on public.casas for update
  using (admin_id = auth.uid())
  with check (admin_id = auth.uid());

-- Moradores
-- Cada um também enxerga o PRÓPRIO registro mesmo depois de removido:
-- é assim que o app descobre que a pessoa saiu da casa.
create policy moradores_select on public.moradores for select
  using (public.eh_membro(casa_id) or usuario_id = auth.uid());
-- Moradores novos entram pela função entrar_na_casa. A inserção direta
-- existe para o admin ao criar a casa (offline) e para o upsert de edições.
create policy moradores_insert on public.moradores for insert
  with check (public.eh_admin(casa_id)
              or (usuario_id = auth.uid() and public.eh_membro(casa_id)));
-- Admin altera/remove qualquer morador; cada um altera só o próprio
-- registro (enquanto ainda está na casa).
create policy moradores_update on public.moradores for update
  using (public.eh_admin(casa_id) or (usuario_id = auth.uid() and not deleted))
  with check (public.eh_admin(casa_id) or usuario_id = auth.uid());

-- Gastos
create policy gastos_select on public.gastos for select
  using (public.eh_membro(casa_id));
create policy gastos_insert on public.gastos for insert
  with check (public.eh_membro(casa_id)
              and (criado_por = auth.uid() or public.eh_admin(casa_id)));
create policy gastos_update on public.gastos for update
  using (public.eh_membro(casa_id)
         and (criado_por = auth.uid() or public.eh_admin(casa_id)))
  with check (public.eh_membro(casa_id));

-- Pagamentos: quem paga, quem recebe ou o admin.
create policy pagamentos_select on public.pagamentos for select
  using (public.eh_membro(casa_id));
create policy pagamentos_insert on public.pagamentos for insert
  with check (public.eh_membro(casa_id) and (
    public.eh_admin(casa_id) or public.eh_meu_morador(de_id) or public.eh_meu_morador(para_id)));
create policy pagamentos_update on public.pagamentos for update
  using (public.eh_membro(casa_id) and (
    public.eh_admin(casa_id) or public.eh_meu_morador(de_id) or public.eh_meu_morador(para_id)))
  with check (public.eh_membro(casa_id));

-- Não existe policy de DELETE: exclusão é sempre lógica (deleted = true).

-- ---------------------------------------------------------------------
-- 4) Entrar numa casa pelo código de convite (precisa de internet).
--    security definer: o usuário ainda não é membro, então não enxergaria
--    a casa pelas policies acima.
--    Quem já morou na casa e foi removido volta com o MESMO registro
--    (mantém o histórico de gastos).
-- ---------------------------------------------------------------------
create or replace function public.entrar_na_casa(p_codigo text, p_nome text)
returns uuid language plpgsql security definer set search_path = public as $$
declare
  v_casa    uuid;
  v_cor     smallint;
  v_morador uuid;
begin
  if auth.uid() is null then
    raise exception 'Faça login primeiro';
  end if;

  select id into v_casa from public.casas
   where codigo_convite = upper(trim(p_codigo)) and not deleted;
  if v_casa is null then
    raise exception 'Código de convite inválido';
  end if;

  select id into v_morador from public.moradores
   where casa_id = v_casa and usuario_id = auth.uid()
   order by deleted asc, updated_at desc
   limit 1;

  if v_morador is null then
    select count(*) % 8 into v_cor from public.moradores where casa_id = v_casa;
    insert into public.moradores (id, casa_id, nome, cor, usuario_id)
    values (gen_random_uuid(), v_casa,
            left(coalesce(nullif(trim(p_nome), ''), 'Morador'), 40),
            v_cor, auth.uid());
  else
    update public.moradores
       set deleted = false, updated_at = now()
     where id = v_morador and deleted;
  end if;

  return v_casa;
end $$;

-- ---------------------------------------------------------------------
-- 5) Transferir a administração para outro morador (precisa de internet).
-- ---------------------------------------------------------------------
create or replace function public.transferir_admin(p_casa uuid, p_morador uuid)
returns void language plpgsql security definer set search_path = public as $$
declare
  v_usuario uuid;
begin
  if not exists (select 1 from public.casas
                  where id = p_casa and admin_id = auth.uid() and not deleted) then
    raise exception 'Só o administrador pode transferir a administração';
  end if;

  select usuario_id into v_usuario from public.moradores
   where id = p_morador and casa_id = p_casa and not deleted
     and usuario_id is not null;
  if v_usuario is null then
    raise exception 'Escolha um morador que tenha conta no app';
  end if;

  update public.casas
     set admin_id = v_usuario, updated_at = now()
   where id = p_casa;
end $$;

grant execute on function public.entrar_na_casa(text, text) to authenticated;
grant execute on function public.transferir_admin(uuid, uuid) to authenticated;
grant execute on function public.eh_membro(uuid) to authenticated;
grant execute on function public.eh_admin(uuid) to authenticated;
grant execute on function public.eh_meu_morador(uuid) to authenticated;

-- ---------------------------------------------------------------------
-- 6) Realtime: o app recebe aviso na hora quando outro morador muda algo
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
